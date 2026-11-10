import Foundation

/// Короткая пауза-приземление между падением и обычной жизнью.
final class LandState: BehaviorState {
    let id: BehaviorID = .land
    let spriteAction: SpriteAction = .land
    let previewFPS: Double = 12

    /// Питомец поднимается ровно за время своей анимации — при любой
    /// настройке скорости. Таймер из конфига остаётся страховкой для пака
    /// с единственным кадром.
    private var playsToEnd = false
    var isInterruptibleByTimer: Bool { !playsToEnd }

    func enter(_ pet: Pet) {
        pet.velocity = .zero
        pet.animator.play(spriteAction, fps: 12, loops: false)
        pet.animator.restart()
        playsToEnd = pet.animator.frameCount > 1
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        pet.animator.play(spriteAction, fps: 12, loops: false)
        return playsToEnd && pet.animator.isFinished ? .done : .stay
    }
}
