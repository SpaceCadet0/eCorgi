import AppKit

/// Модель питомца: физическое состояние + связка движка и автомата поведений.
/// `Pet` играет роль «режиссёра»: сначала обрабатывает события, которые
/// перебивают любое поведение (перетаскивание, потеря опоры, курсор рядом),
/// и только потом отдаёт тик текущему состоянию.
public final class Pet {

    // MARK: - Физическое состояние

    /// Точка под лапами: низ-центр спрайта, координаты AppKit.
    public var position: CGPoint
    public var velocity: CGVector = .zero
    /// +1 — смотрит вправо, -1 — влево.
    public var facing: CGFloat = 1

    /// Полка, на которой стоит питомец. `nil` — в воздухе.
    public private(set) var support: Ledge?
    /// Сколько секунд питомец практически не двигался — по этому растёт шанс сна.
    public private(set) var timeSinceMoved: TimeInterval = 0
    /// Накопленное время деятельных состояний. Дойдя до `sleepAfterActivity`,
    /// питомец укладывается спать; сон обнуляет счётчик.
    public private(set) var activeTime: TimeInterval = 0
    /// Сколько секунд питомец не спускался с окон на пол.
    public private(set) var timeOnWindow: TimeInterval = 0

    // MARK: - Взаимодействие

    public var isDragged: Bool = false
    /// Куда тянет курсор во время перетаскивания (точка под лапами).
    public var dragTarget: CGPoint = .zero

    /// Грань, по которой питомец сейчас лезет.
    public var climbTarget: Wall?
    /// Грань, на которой он висит.
    public var hangAnchor: HangAnchor?
    /// Наклон спрайта, радианы — покачивание на лапах во время подвеса.
    public var sway: CGFloat = 0

    // MARK: - Зависимости

    public let atlas: SpriteAtlas
    public let animator: SpriteAnimator
    public let environment: ScreenEnvironment
    public let cursor: CursorTracker
    public let settings: SettingsStore
    public let random: RandomSource
    public var tuning: BehaviorTuning

    private var machine: StateMachine!

    /// Спокойные наземные состояния: питомец на опоре и ничем не занят.
    /// По ним движок решает, что список окон можно опрашивать пореже.
    private static let ambient: Set<BehaviorID> = [.idle, .walk, .sit, .scratch,
                                                   .settleDown, .sleep, .wakeUp]

    /// Из чего питомца может спугнуть курсор.
    ///
    /// Сон и укладывание сюда не входят: спящего мышь не поднимает. Разбудить
    /// его можно, только взяв в руки или через меню в строке меню.
    private static let startleable: Set<BehaviorID> = ambient.subtracting([.settleDown, .sleep])
    /// Состояния, в которых питомец отдыхает: время в них не идёт в усталость.
    private static let restful: Set<BehaviorID> = [.idle, .sit, .settleDown, .sleep, .wakeUp]
    /// Состояния, которые сами отвечают за отсутствие опоры под лапами.
    private static let airborne: Set<BehaviorID> = [.fall, .climb, .hang, .hop, .jumpDown]
    /// Откуда нельзя просто взять и заснуть — сорвётся или зависнет в воздухе.
    private static let unsafeForSleep: Set<BehaviorID> = [.climb, .hang, .fall, .drag, .hop, .jumpDown]

    public init(atlas: SpriteAtlas,
                environment: ScreenEnvironment = ScreenEnvironment(),
                cursor: CursorTracker = CursorTracker(),
                settings: SettingsStore = .shared,
                config: BehaviorConfig = .load(),
                random: RandomSource = .system,
                position: CGPoint? = nil) {
        self.atlas = atlas
        self.animator = SpriteAnimator(atlas: atlas)
        self.environment = environment
        self.cursor = cursor
        self.settings = settings
        self.random = random
        self.tuning = config.tuning

        let ground = environment.ledges.first { $0.kind == .ground }
        self.position = position ?? CGPoint(x: (ground.map { ($0.minX + $0.maxX) / 2 }) ?? 200,
                                            y: ground?.y ?? 0)

        self.machine = StateMachine(config: config, states: Pet.makeStates(), initial: .idle, random: random)
        self.machine.current.enter(self)
    }

    static func makeStates() -> [BehaviorID: BehaviorState] {
        let all: [BehaviorState] = [
            IdleState(), WalkState(), SitState(), ScratchState(),
            SettleDownState(), SleepState(), WakeUpState(),
            RunFromCursorState(), ClimbState(), HangState(),
            HopState(), JumpDownState(),
            FallState(), LandState(), DragState()
        ]
        return Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }

    public var currentBehavior: BehaviorID { machine.current.id }

    /// Скорость с учётом пользовательской настройки.
    public var speedFactor: CGFloat { CGFloat(settings.speedMultiplier) }

    // MARK: - Тик

    public func update(_ dt: TimeInterval) {
        environment.windowAwareness = settings.windowAwareness
        environment.update(dt, urgency: environmentUrgency)
        cursor.update(dt)

        refreshSupport()
        trackTimeOnWindow(dt)
        applyDirectorOverrides()

        let before = position
        machine.update(self, dt: dt)
        animator.update(dt * settings.speedMultiplier)

        if !Pet.restful.contains(currentBehavior) { activeTime += dt }

        timeSinceMoved = hypot(position.x - before.x, position.y - before.y) > 0.3 ? 0 : timeSinceMoved + dt
        clampToWorld()
    }

    /// Насколько часто сейчас нужен свежий список окон.
    ///
    /// Питомец работает только с передним окном, а оно меняется в тот же миг,
    /// когда пользователь щёлкает мышью. Поэтому всё, что происходит наверху
    /// или в воздухе, требует свежей геометрии: иначе питомец успевает
    /// постоять на полке, которой уже нет.
    private var environmentUrgency: ScreenEnvironment.Urgency {
        if isDragged { return .high }
        if support == nil || support?.kind == .windowTop { return .high }
        return Pet.ambient.contains(currentBehavior) && abs(velocity.dx) < 1 ? .low : .normal
    }

    /// Частота кадров, которой сейчас достаточно: пока питомец стоит или спит,
    /// 30 fps ни к чему.
    public var desiredFPS: Double {
        switch currentBehavior {
        case .sleep, .sit:                       return 10
        case .idle, .scratch, .settleDown, .wakeUp: return 15
        case .hang:                   return 20
        default:                      return 30
        }
    }

    /// Принудительная смена поведения — из меню статус-бара или по событию мыши.
    public func force(_ id: BehaviorID) {
        machine.force(id, pet: self)
    }

    // MARK: - Внутреннее

    private func refreshSupport() {
        support = PhysicsHelper.support(at: position, in: environment.ledges)
    }

    /// Счётчик обнуляется только на полу: в прыжке и на подвесе опоры нет,
    /// но это ещё не значит, что питомец спустился.
    private func trackTimeOnWindow(_ dt: TimeInterval) {
        switch support?.kind {
        case .ground:    timeOnWindow = 0
        case .windowTop: timeOnWindow += dt
        case nil:        break
        }
    }

    /// Пора спускаться: питомец слишком долго не сходит с окон.
    public var hasOverstayedOnWindow: Bool {
        support?.kind == .windowTop && timeOnWindow > tuning.windowStayLimit
    }

    private func applyDirectorOverrides() {
        let state = machine.current.id

        if isDragged {
            if state != .drag { machine.force(.drag, pet: self) }
            return
        }
        if state == .drag {
            machine.force(.fall, pet: self)
            return
        }
        // Лазание, подвес и прыжки идут без опоры под лапами по определению —
        // эти состояния сами доводят себя до полки.
        if support == nil, !Pet.airborne.contains(state) {
            machine.force(.fall, pet: self)
            return
        }
        // Курсор проверяем раньше усталости: спугнуть питомца важнее, чем уложить.
        if settings.reactToCursor,
           Pet.startleable.contains(state),
           cursor.distance(to: CGPoint(x: position.x, y: position.y + spriteHeightHint / 2)) < tuning.cursorFleeRadius {
            machine.force(.runFromCursor, pet: self)
            return
        }
        // Не в сон напрямую: укладывание — обязательная прелюдия.
        if isTired, canFallAsleep {
            machine.force(.settleDown, pet: self)
        }
    }

    /// Спит или уже укладывается — для пункта меню и внешних команд.
    public var isAsleep: Bool {
        currentBehavior == .sleep || currentBehavior == .settleDown
    }

    /// Набегало ли достаточно деятельного времени, чтобы захотеть спать.
    public var isTired: Bool { activeTime >= tuning.sleepAfterActivity }

    /// Уснуть можно только стоя на опоре: с грани окна или в полёте — сорвётся.
    private var canFallAsleep: Bool {
        support != nil && !isDragged
            && !Pet.unsafeForSleep.contains(currentBehavior)
            && currentBehavior != .sleep && currentBehavior != .wakeUp
    }

    /// Отдых после сна.
    ///
    /// Счётчик снимает только сон от усталости. Дрёма от скуки (переход в сон
    /// по условию `rested`) его не трогает: иначе порог в две минуты был бы
    /// недостижим — питомец успевал бы задремать раньше, обнулял накопленное,
    /// и «сон после N минут активности» не наступал бы никогда.
    func recoverFromSleep() {
        guard isTired else { return }
        activeTime = 0
    }

    /// Грубая оценка высоты питомца — нужна, чтобы мерить расстояние до курсора
    /// от середины тела, а не от лап.
    public var spriteHeightHint: CGFloat {
        animator.currentFrame.size.height * CGFloat(settings.scale)
    }

    private func clampToWorld() {
        let bounds = environment.worldBounds
        guard !bounds.isNull else { return }
        position.x = position.x.clamped(to: bounds.minX...bounds.maxX)
        // Провалившегося ниже всех экранов возвращаем на пол.
        if position.y < bounds.minY - 200 {
            position.y = bounds.minY
            velocity = .zero
        }
    }

    /// Полка, по которой сейчас можно идти (или ближайший пол).
    public func walkableLedge() -> Ledge? {
        support ?? environment.ledges.first { $0.kind == .ground && $0.contains(x: position.x) }
    }

    // MARK: - Размеры спрайта

    /// Габариты берём по самому большому кадру атласа, а не по текущему:
    /// иначе при смене кадра питомец, висящий на грани, дёргался бы вверх-вниз.
    public var spriteWidth: CGFloat { atlas.maxFrameSize.width * CGFloat(settings.scale) }
    public var spriteHeight: CGFloat { atlas.maxFrameSize.height * CGFloat(settings.scale) }

    /// Насколько центр спрайта отстоит от грани, за которую питомец держится.
    public var wallHugOffset: CGFloat { spriteWidth * 0.22 }

    /// Где оказывается тело питомца, взявшегося за вертикальную грань.
    ///
    /// Обычно — снаружи окна. Но грани окон во весь экран стоят вплотную к его
    /// краю, и «снаружи» означало бы за пределами видимой области, поэтому
    /// в таком случае питомец лезет по внутренней стороне.
    public func bodyX(besideEdgeAt x: CGFloat, side: HorizontalSide) -> CGFloat {
        let outside = x + side.outward * wallHugOffset
        let bounds = environment.worldBounds
        guard !bounds.isNull else { return outside }
        guard outside < bounds.minX || outside > bounds.maxX else { return outside }
        return x - side.outward * wallHugOffset
    }
    /// Насколько вглубь полки он переступает, забравшись наверх.
    public var ledgeStepInset: CGFloat { spriteWidth * 0.3 }

    // MARK: - Поиск граней

    /// Грань, за которую питомец может ухватиться прямо сейчас.
    /// `direction` задаётся при ходьбе, чтобы он цеплялся за стену перед собой,
    /// а не за ту, которую только что миновал.
    /// `maxDistance` расширяет поиск: с ним же питомец выбирает, к какой грани
    /// стоит прогуляться, а не только за какую можно взяться прямо сейчас.
    public func climbableWall(direction: CGFloat? = nil, maxDistance: CGFloat? = nil) -> Wall? {
        let limit = maxDistance ?? (tuning.wallReach + wallHugOffset)
        return environment.walls
            .filter { wall in
                let dx = wall.x - position.x
                guard abs(dx) <= limit else { return false }
                // Грань должна быть перед питомцем: иначе, уходя от окна,
                // он на каждом тике заново решал бы на него залезть.
                if let direction, dx * direction < -2 { return false }
                // Лезть есть куда и есть за что ухватиться с текущей высоты.
                guard wall.maxY >= position.y + tuning.minClimbHeight else { return false }
                guard wall.minY <= position.y + tuning.wallGrabReach else { return false }
                return true
            }
            .min { abs($0.x - position.x) < abs($1.x - position.x) }
    }

    /// На каком расстоянии от конца полки питомец может за неё ухватиться.
    public static let edgeGrabDistance: CGFloat = 40

    /// Точка подвеса, если питомец стоит у самого конца верхней грани окна.
    public func hangAnchorAtEdge(distance: CGFloat = Pet.edgeGrabDistance) -> HangAnchor? {
        guard let ledge = support, ledge.kind == .windowTop else { return nil }
        if abs(position.x - ledge.minX) <= distance {
            return HangAnchor(x: ledge.minX, y: ledge.y, side: .left)
        }
        if abs(position.x - ledge.maxX) <= distance {
            return HangAnchor(x: ledge.maxX, y: ledge.y, side: .right)
        }
        return nil
    }

    /// Край, с которого спрыгивание имеет смысл.
    ///
    /// Наружу от края должно оставаться место в пределах экрана. Иначе прыжок
    /// упирается в границу мира, `clampToWorld` гасит горизонтальный разгон,
    /// и вместо прыжка получается сползание по стенке.
    public func jumpDownAnchor() -> HangAnchor? {
        guard let anchor = hangAnchorAtEdge() else { return nil }
        let bounds = environment.worldBounds
        guard !bounds.isNull else { return anchor }
        let landingX = anchor.x + anchor.side.outward * spriteWidth
        return landingX > bounds.minX && landingX < bounds.maxX ? anchor : nil
    }

    /// Та же грань в свежем списке окон: окно могло сдвинуться или закрыться,
    /// поэтому объект из прошлого тика переискивается по геометрии.
    public func refreshedClimbTarget() -> Wall? {
        guard let target = climbTarget else { return nil }
        let match = environment.walls.first {
            $0.side == target.side
                && abs($0.x - target.x) <= 8
                && $0.maxY >= position.y - 4
                && position.y >= $0.minY - tuning.wallGrabReach - 20
        }
        climbTarget = match
        return match
    }

    /// Жива ли ещё грань, на которой висит питомец.
    public func refreshedHangAnchor() -> HangAnchor? {
        guard let anchor = hangAnchor else { return nil }
        let match = environment.ledges.first {
            $0.kind == .windowTop
                && abs($0.y - anchor.y) <= 8
                && abs((anchor.side == .left ? $0.minX : $0.maxX) - anchor.x) <= 12
        }
        guard let ledge = match else {
            hangAnchor = nil
            return nil
        }
        let refreshed = HangAnchor(x: anchor.side == .left ? ledge.minX : ledge.maxX,
                                   y: ledge.y,
                                   side: anchor.side)
        hangAnchor = refreshed
        return refreshed
    }
}
