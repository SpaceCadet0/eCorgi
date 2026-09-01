import Foundation

/// Ходьба по текущей полке.
///
/// Здесь же живут входы в «оконные» поведения: упёршись в вертикальную
/// грань окна, питомец может полезть наверх, а дойдя до конца верхней грани —
/// свеситься с неё, спрыгнуть вниз или развернуться.
///
/// Прогулка бывает двух видов: бесцельная (её обрывает таймер автомата) и
/// с целью — дойти до конкретной грани. Вторая таймером не прерывается,
/// иначе на экране с окнами во всю ширину питомец разворачивался бы
/// на полпути и до граней не добирался бы вовсе.
final class WalkState: BehaviorState {
    let id: BehaviorID = .walk

    /// Отступ от края полки, на котором считаем, что дошли.
    private let edgeMargin: CGFloat = 6
    /// Не пытаться лезть на стену чаще, чем раз в столько секунд —
    /// иначе питомец топчется у грани, каждый тик бросая кубик.
    private let climbCooldown: TimeInterval = 1.0
    /// Страховка: если до цели почему-то не дойти, прогулка всё равно кончится.
    private let goalTimeout: TimeInterval = 20

    private var timeSinceClimbAttempt: TimeInterval = .greatestFiniteMagnitude
    private var goalX: CGFloat?
    private var goalElapsed: TimeInterval = 0

    /// Пока идём к цели, автомат прогулку не обрывает.
    var isInterruptibleByTimer: Bool { goalX == nil }

    func enter(_ pet: Pet) {
        timeSinceClimbAttempt = .greatestFiniteMagnitude
        goalElapsed = 0
        pet.velocity = .zero

        if let edge = edgeToLeaveBy(pet) {
            goalX = edge
            pet.facing = edge > pet.position.x ? 1 : -1
        } else if let wall = wallWorthWalkingTo(pet) {
            goalX = wall.x
            pet.facing = wall.x > pet.position.x ? 1 : -1
        } else {
            goalX = nil
            pet.facing = pet.random.chance(0.5) ? 1 : -1
        }
    }

    /// Ближайший край окна, если питомец на нём засиделся.
    /// Заголовок бывает шириной во весь экран, и случайное блуждание по нему
    /// почти никогда не доводит до края — приходится вести целенаправленно.
    private func edgeToLeaveBy(_ pet: Pet) -> CGFloat? {
        guard pet.hasOverstayedOnWindow, let ledge = pet.support else { return nil }
        return abs(pet.position.x - ledge.minX) < abs(pet.position.x - ledge.maxX)
            ? ledge.minX : ledge.maxX
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        guard let ledge = pet.walkableLedge() else { return .switchTo(.fall) }

        pet.animator.play(.walk, fps: pet.tuning.walkFPS)
        timeSinceClimbAttempt += dt
        trackGoal(pet, dt: dt)

        if let transition = tryClimb(pet) { return transition }

        let step = pet.tuning.walkSpeed * pet.speedFactor * CGFloat(dt) * pet.facing
        let nextX = pet.position.x + step

        // Край засчитывается, только если питомец в него идёт. Без этой
        // проверки он застревал в углу экрана: оказавшись ближе edgeMargin к
        // концу полки, он на каждом тике «упирался в край» независимо от
        // направления и разворачивался туда-обратно, не сходя с места.
        if pet.facing < 0, nextX < ledge.minX + edgeMargin {
            return handleEdge(pet, ledge: ledge, side: .left)
        }
        if pet.facing > 0, nextX > ledge.maxX - edgeMargin {
            return handleEdge(pet, ledge: ledge, side: .right)
        }

        pet.position.x = nextX
        pet.position.y = ledge.y
        return .stay
    }

    func exit(_ pet: Pet) {
        goalX = nil
    }

    // MARK: - Цель прогулки

    /// Грань, к которой имеет смысл прогуляться. Решение бросается один раз
    /// на входе в состояние, а не каждый тик.
    private func wallWorthWalkingTo(_ pet: Pet) -> Wall? {
        guard pet.settings.windowAwareness,
              pet.random.chance(pet.tuning.seekWallChance),
              let wall = pet.climbableWall(maxDistance: pet.tuning.wallSeekRange),
              abs(wall.x - pet.position.x) > pet.wallHugOffset
        else { return nil }
        return wall
    }

    private func trackGoal(_ pet: Pet, dt: TimeInterval) {
        guard let goal = goalX else { return }
        goalElapsed += dt
        // Дошли или слишком долго идём — дальше гуляем как обычно.
        if goalElapsed >= goalTimeout || abs(pet.position.x - goal) <= pet.wallHugOffset + pet.tuning.wallReach {
            goalX = nil
        }
    }

    /// Разворот всегда отменяет цель: идти к ней спиной вперёд бессмысленно.
    private func turnAround(_ pet: Pet) {
        pet.facing *= -1
        goalX = nil
    }

    // MARK: - Переходы в «оконные» состояния

    /// Упёрлись в грань окна — может, наверх?
    private func tryClimb(_ pet: Pet) -> BehaviorTransition? {
        guard pet.settings.windowAwareness,
              timeSinceClimbAttempt >= climbCooldown,
              let wall = pet.climbableWall(direction: pet.facing)
        else { return nil }

        timeSinceClimbAttempt = 0
        guard pet.random.chance(pet.tuning.climbChance) else {
            // Передумал — разворачиваемся, чтобы не упираться в стену носом.
            turnAround(pet)
            return .stay
        }
        pet.climbTarget = wall
        return .switchTo(.climb)
    }

    /// Дошли до конца полки.
    private func handleEdge(_ pet: Pet, ledge: Ledge, side: HorizontalSide) -> BehaviorTransition {
        // С края экрана прыгать некуда — только разворот.
        guard ledge.kind == .windowTop else {
            turnAround(pet)
            return .stay
        }

        // Засиделся наверху — спускаемся не раздумывая.
        if pet.hasOverstayedOnWindow {
            pet.position.x = side == .left ? ledge.minX : ledge.maxX
            if pet.jumpDownAnchor() != nil { return .switchTo(.jumpDown) }
        }

        let roll = pet.random.unit()

        if roll < pet.tuning.edgeHangChance {
            pet.position.x = side == .left ? ledge.minX : ledge.maxX
            pet.hangAnchor = HangAnchor(x: pet.position.x, y: ledge.y, side: side)
            return .switchTo(.hang)
        }
        if roll < pet.tuning.edgeHangChance + pet.tuning.edgeJumpDownChance {
            // Встаём ровно на край: спрыгивание само возьмёт отсюда сторону и толчок.
            pet.position.x = side == .left ? ledge.minX : ledge.maxX
            // У края экрана прыгать наружу некуда — тогда просто разворот.
            if pet.jumpDownAnchor() != nil { return .switchTo(.jumpDown) }
        }

        turnAround(pet)
        return .stay
    }
}
