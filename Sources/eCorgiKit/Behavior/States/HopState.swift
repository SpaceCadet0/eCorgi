import Foundation

/// Подскок на месте — игривое поведение «от избытка сил».
/// Обычная баллистика: толчок вверх, дальше всё решает гравитация,
/// поэтому питомец приземляется ровно туда, откуда оттолкнулся.
final class HopState: BehaviorState {
    let id: BehaviorID = .hop
    /// Кончается приземлением, а не таймером автомата.
    let isInterruptibleByTimer = false

    func enter(_ pet: Pet) {
        // Оттолкнуться можно только от опоры.
        guard pet.support != nil else { return }
        pet.velocity = CGVector(dx: 0, dy: pet.tuning.hopSpeed * pet.speedFactor)
        pet.animator.play(.jump, fps: 12, loops: false)
        pet.animator.restart()
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        // Оттолкнуться не удалось (опоры не было) — просто возвращаемся к жизни.
        guard pet.velocity.dy != 0 || pet.support == nil else { return .switchTo(.idle) }

        pet.animator.play(.jump, fps: 12, loops: false)

        let step = PhysicsHelper.advanceThroughAir(position: pet.position,
                                                   velocity: pet.velocity,
                                                   dt: CGFloat(dt),
                                                   in: pet.environment.ledges)
        pet.position = step.position
        pet.velocity = step.velocity
        return step.landing == nil ? .stay : .switchTo(.land)
    }
}
