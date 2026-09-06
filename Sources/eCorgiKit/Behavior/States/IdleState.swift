import Foundation

/// Стоит на месте, дышит. Базовая «развилка» между остальными поведениями.
final class IdleState: BehaviorState {
    let id: BehaviorID = .idle
    let spriteAction: SpriteAction = .idle
    let previewFPS: Double = 5

    func enter(_ pet: Pet) {
        pet.velocity = .zero
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        pet.animator.play(spriteAction, fps: pet.tuning.idleFPS)
        return .stay
    }
}
