import Foundation

/// Короткая пауза-приземление между падением и обычной жизнью.
final class LandState: BehaviorState {
    let id: BehaviorID = .land

    func enter(_ pet: Pet) {
        pet.velocity = .zero
        pet.animator.play(.land, fps: 12, loops: false)
        pet.animator.restart()
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        .stay
    }
}
