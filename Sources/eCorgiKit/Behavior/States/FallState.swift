import Foundation

/// Свободное падение до ближайшей полки снизу. Горизонтальная скорость
/// сохраняется — так падение после шага с окна выглядит как прыжок.
final class FallState: BehaviorState {
    let id: BehaviorID = .fall
    /// Падение заканчивается только приземлением, а не таймером автомата.
    let isInterruptibleByTimer = false

    /// Затухание горизонтальной скорости в воздухе.
    private let airDrag: CGFloat = 0.4

    func enter(_ pet: Pet) {
        pet.animator.play(.fall, fps: 10, loops: false)
        if pet.velocity.dy > 0 { pet.velocity.dy = 0 }
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        pet.animator.play(.fall, fps: 10, loops: false)

        let step = PhysicsHelper.advanceThroughAir(position: pet.position,
                                                   velocity: pet.velocity,
                                                   dt: CGFloat(dt),
                                                   airDrag: airDrag,
                                                   in: pet.environment.ledges)
        pet.position = step.position
        pet.velocity = step.velocity
        return step.landing == nil ? .stay : .switchTo(.land)
    }
}
