import Foundation

/// Стоит на месте, дышит. Базовая «развилка» между остальными поведениями.
final class IdleState: BehaviorState {
    let id: BehaviorID = .idle

    func enter(_ pet: Pet) {
        pet.velocity = .zero
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        pet.animator.play(.idle, fps: pet.tuning.idleFPS)
        return .stay
    }
}
