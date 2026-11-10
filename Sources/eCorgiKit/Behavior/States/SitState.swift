import Foundation

/// Сидит. Из этого состояния чаще всего уходит в сон.
final class SitState: BehaviorState {
    let id: BehaviorID = .sit
    let spriteAction: SpriteAction = .sit
    let previewFPS: Double = 7.2

    /// Кадры `sit` — законченная сценка: сел, огляделся, встал. Поэтому она
    /// играется один раз и целиком. По таймеру её обрывало на середине, и
    /// сидящий питомец одним кадром оказывался идущим.
    private var playsToEnd = false
    var isInterruptibleByTimer: Bool { !playsToEnd }

    func enter(_ pet: Pet) {
        pet.velocity = .zero
        pet.animator.play(spriteAction, fps: pet.tuning.idleFPS * 0.6, loops: false)
        pet.animator.restart()
        playsToEnd = pet.animator.frameCount > 1
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        pet.animator.play(spriteAction, fps: pet.tuning.idleFPS * 0.6, loops: false)
        return playsToEnd && pet.animator.isFinished ? .done : .stay
    }
}
