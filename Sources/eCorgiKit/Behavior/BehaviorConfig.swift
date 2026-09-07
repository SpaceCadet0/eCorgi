import Foundation

/// Условие применимости перехода. Проверяется в момент выбора следующего состояния.
public enum BehaviorCondition: String, Codable, Sendable {
    case always
    /// Питомец стоит на опоре.
    case onGround
    /// Опора — верхняя грань чужого окна, а не пол экрана.
    case onWindowLedge
    /// Питомец давно не двигался — повод задремать.
    case rested
    /// Рядом есть вертикальная грань окна, за которую можно ухватиться.
    case nearWall
    /// Питомец стоит у самого конца верхней грани окна.
    case atLedgeEdge
    /// Питомец у края, с которого есть куда спрыгнуть.
    case canJumpDown
    /// Полон сил: усталость ещё не набрана и наполовину. Для игривых
    /// поведений вроде прыжков на месте.
    case energetic
}

/// Взвешенный переход в следующее состояние.
public struct BehaviorTransitionRule: Codable, Sendable {
    public var state: BehaviorID
    public var weight: Double
    public var condition: BehaviorCondition

    private enum CodingKeys: String, CodingKey { case state, weight, condition }

    public init(state: BehaviorID, weight: Double, condition: BehaviorCondition = .always) {
        self.state = state
        self.weight = weight
        self.condition = condition
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(BehaviorID.self, forKey: .state)
        weight = try container.decodeIfPresent(Double.self, forKey: .weight) ?? 1
        condition = try container.decodeIfPresent(BehaviorCondition.self, forKey: .condition) ?? .always
    }
}

/// Описание одного состояния в конфиге.
public struct BehaviorDefinition: Codable, Sendable {
    public var minDuration: TimeInterval
    public var maxDuration: TimeInterval
    public var next: [BehaviorTransitionRule]

    private enum CodingKeys: String, CodingKey { case minDuration, maxDuration, next }

    public init(minDuration: TimeInterval, maxDuration: TimeInterval, next: [BehaviorTransitionRule]) {
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.next = next
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .minDuration) ?? 1
        maxDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .maxDuration) ?? 3
        next = try container.decodeIfPresent([BehaviorTransitionRule].self, forKey: .next) ?? []
    }

    /// Случайная длительность в заданном диапазоне.
    public func duration(using random: RandomSource) -> TimeInterval {
        guard maxDuration > minDuration else { return minDuration }
        return random.value(in: minDuration...maxDuration)
    }
}

/// Числовые параметры «характера» — вынесены в JSON, чтобы крутить
/// без пересборки (пригодится и для будущих скинов/пород).
public struct BehaviorTuning: Codable, Sendable {
    public var walkSpeed: CGFloat = 55
    public var runSpeed: CGFloat = 170
    public var cursorFleeRadius: CGFloat = 90
    public var cursorCalmRadius: CGFloat = 240
    public var dragFollowStiffness: CGFloat = 14
    public var walkFPS: Double = 12
    public var runFPS: Double = 18
    public var idleFPS: Double = 5

    /// Сколько секунд деятельной жизни (ходьба, бег, лазание, подвес, возня)
    /// питомец выдерживает, прежде чем уйти спать. Стояние и сидение не в счёт.
    public var sleepAfterActivity: TimeInterval = 120

    // MARK: Лазание по граням окон

    /// Скорость подъёма по вертикальной грани, пунктов/с.
    public var climbSpeed: CGFloat = 110
    /// На каком расстоянии по горизонтали питомец «дотягивается» до грани.
    public var wallReach: CGFloat = 10
    /// Насколько выше лап может начинаться грань, чтобы за неё ещё можно было
    /// ухватиться в прыжке.
    public var wallGrabReach: CGFloat = 70
    /// Ниже этого подъёма лезть незачем — проще обойти.
    public var minClimbHeight: CGFloat = 70
    /// Вероятность полезть наверх, упёршись в грань окна.
    public var climbChance: Double = 0.55
    /// Вероятность, начиная прогулку, целенаправленно пойти к ближайшей грани,
    /// а не в случайную сторону. Без этого на экране с окнами во всю ширину
    /// питомец почти никогда не добредает до края и не лазает вовсе.
    public var seekWallChance: Double = 0.4
    /// Как далеко он готов идти к грани.
    public var wallSeekRange: CGFloat = 1000
    /// Сколько секунд питомец готов провести на одном окне, прежде чем
    /// начнёт целенаправленно спускаться. Без этого он, забравшись наверх,
    /// бродил по широкому заголовку и вниз практически не возвращался.
    public var windowStayLimit: TimeInterval = 30

    // MARK: Поведение на краю верхней грани окна

    /// Шанс свеситься с края окна.
    public var edgeHangChance: Double = 0.35
    /// Шанс спрыгнуть с края вниз.
    public var edgeJumpDownChance: Double = 0.25
    /// Сколько висеть, секунд.
    public var hangMinDuration: TimeInterval = 2.5
    public var hangMaxDuration: TimeInterval = 6.0
    /// Шанс подтянуться обратно на грань, а не разжать лапы.
    public var hangPullUpChance: Double = 0.6
    // MARK: Прыжки

    /// Начальная скорость подскока на месте, пунктов/с.
    /// Аналитическая высота — hopSpeed² / (2 · gravity), но пошаговое
    /// интегрирование на 30 fps недобирает около пятой части: при 320
    /// фактический подскок выходит ~20 пунктов, а не расчётные 26.
    public var hopSpeed: CGFloat = 320
    /// На сколько своих длин питомец перелетает в подскоке.
    /// Ноль — подскок строго вверх, как было раньше.
    public var hopLengths: CGFloat = 3

    /// Горизонтальный разгон при спрыгивании с края.
    public var jumpSpeed: CGFloat = 145
    /// Подброс вверх в начале прыжка — без него получается не прыжок, а шаг в пустоту.
    public var jumpLift: CGFloat = 200
    /// Сопротивление воздуха в прыжке. Меньше, чем при падении: прыжок
    /// должен доносить питомца вперёд.
    public var jumpAirDrag: CGFloat = 0.15

    /// Амплитуда покачивания на лапах, радианы.
    public var hangSwayAmplitude: CGFloat = 0.13
    /// Период покачивания, секунд.
    public var hangSwayPeriod: TimeInterval = 1.8

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case walkSpeed, runSpeed, cursorFleeRadius, cursorCalmRadius, dragFollowStiffness
        case walkFPS, runFPS, idleFPS, sleepAfterActivity
        case climbSpeed, wallReach, wallGrabReach, minClimbHeight, climbChance
        case seekWallChance, wallSeekRange, windowStayLimit
        case edgeHangChance, edgeJumpDownChance
        case hopSpeed, hopLengths, jumpSpeed, jumpLift, jumpAirDrag
        case hangMinDuration, hangMaxDuration, hangPullUpChance
        case hangSwayAmplitude, hangSwayPeriod
    }

    /// Каждое поле читается по отдельности и с запасным значением.
    /// Иначе один недостающий ключ в `behaviors.json` ронял бы разбор целиком,
    /// и приложение молча уезжало на встроенный минимальный конфиг.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BehaviorTuning()
        func number<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            guard let decoded = try? c.decodeIfPresent(T.self, forKey: key) else { return fallback }
            return decoded ?? fallback
        }
        walkSpeed = number(.walkSpeed, d.walkSpeed)
        runSpeed = number(.runSpeed, d.runSpeed)
        cursorFleeRadius = number(.cursorFleeRadius, d.cursorFleeRadius)
        cursorCalmRadius = number(.cursorCalmRadius, d.cursorCalmRadius)
        dragFollowStiffness = number(.dragFollowStiffness, d.dragFollowStiffness)
        walkFPS = number(.walkFPS, d.walkFPS)
        runFPS = number(.runFPS, d.runFPS)
        idleFPS = number(.idleFPS, d.idleFPS)
        sleepAfterActivity = number(.sleepAfterActivity, d.sleepAfterActivity)
        climbSpeed = number(.climbSpeed, d.climbSpeed)
        wallReach = number(.wallReach, d.wallReach)
        wallGrabReach = number(.wallGrabReach, d.wallGrabReach)
        minClimbHeight = number(.minClimbHeight, d.minClimbHeight)
        climbChance = number(.climbChance, d.climbChance)
        seekWallChance = number(.seekWallChance, d.seekWallChance)
        wallSeekRange = number(.wallSeekRange, d.wallSeekRange)
        windowStayLimit = number(.windowStayLimit, d.windowStayLimit)
        edgeHangChance = number(.edgeHangChance, d.edgeHangChance)
        edgeJumpDownChance = number(.edgeJumpDownChance, d.edgeJumpDownChance)
        hopSpeed = number(.hopSpeed, d.hopSpeed)
        hopLengths = number(.hopLengths, d.hopLengths)
        jumpSpeed = number(.jumpSpeed, d.jumpSpeed)
        jumpLift = number(.jumpLift, d.jumpLift)
        jumpAirDrag = number(.jumpAirDrag, d.jumpAirDrag)
        hangMinDuration = number(.hangMinDuration, d.hangMinDuration)
        hangMaxDuration = number(.hangMaxDuration, d.hangMaxDuration)
        hangPullUpChance = number(.hangPullUpChance, d.hangPullUpChance)
        hangSwayAmplitude = number(.hangSwayAmplitude, d.hangSwayAmplitude)
        hangSwayPeriod = number(.hangSwayPeriod, d.hangSwayPeriod)
    }
}

/// Корневой формат `behaviors.json`.
public struct BehaviorConfig: Codable, Sendable {
    public var states: [BehaviorID: BehaviorDefinition]
    public var tuning: BehaviorTuning

    private enum CodingKeys: String, CodingKey { case states, tuning }

    public init(states: [BehaviorID: BehaviorDefinition], tuning: BehaviorTuning = BehaviorTuning()) {
        self.states = states
        self.tuning = tuning
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent([String: BehaviorDefinition].self, forKey: .states) ?? [:]
        var states: [BehaviorID: BehaviorDefinition] = [:]
        for (key, value) in raw {
            guard let id = BehaviorID(rawValue: key) else { continue }
            states[id] = value
        }
        self.states = states
        self.tuning = try container.decodeIfPresent(BehaviorTuning.self, forKey: .tuning) ?? BehaviorTuning()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Dictionary(uniqueKeysWithValues: states.map { ($0.key.rawValue, $0.value) }), forKey: .states)
        try container.encode(tuning, forKey: .tuning)
    }

    /// Конфиг из бандла; если файла нет или он битый — встроенный запасной.
    public static func load(from url: URL? = nil) -> BehaviorConfig {
        let url = url ?? ResourceBundle.url(forResource: "behaviors", withExtension: "json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(BehaviorConfig.self, from: data),
              !config.states.isEmpty
        else { return .fallback }
        return config
    }

    /// Минимальный рабочий набор на случай отсутствия ресурса.
    public static let fallback = BehaviorConfig(states: [
        .idle: BehaviorDefinition(minDuration: 1.5, maxDuration: 4, next: [
            BehaviorTransitionRule(state: .walk, weight: 60),
            BehaviorTransitionRule(state: .sit, weight: 40)
        ]),
        .walk: BehaviorDefinition(minDuration: 2, maxDuration: 6, next: [
            BehaviorTransitionRule(state: .idle, weight: 100)
        ]),
        .sit: BehaviorDefinition(minDuration: 2, maxDuration: 6, next: [
            BehaviorTransitionRule(state: .idle, weight: 100)
        ])
    ])
}
