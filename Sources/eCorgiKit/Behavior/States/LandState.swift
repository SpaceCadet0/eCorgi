import Foundation

/// Короткая пауза-приземление между падением и обычной жизнью.
final class LandState: BehaviorState {
    let id: BehaviorID = .land
    let spriteAction: SpriteAction = .land
    let previewFPS: Double = 12

    func enter(_ pet: Pet) {
        pet.velocity = .zero
        pet.animator.play(spriteAction, fps: 12, loops: false)
        pet.animator.restart()
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        .stay
    }
}
