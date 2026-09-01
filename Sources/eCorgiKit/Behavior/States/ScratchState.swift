import Foundation

/// Чешется — короткое «характерное» поведение, разбавляющее простой.
final class ScratchState: BehaviorState {
    let id: BehaviorID = .scratch

    func enter(_ pet: Pet) {
        pet.velocity = .zero
        pet.animator.play(.scratch, fps: 10)
        pet.animator.restart()
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        pet.animator.play(.scratch, fps: 10)
        return .stay
    }
}
