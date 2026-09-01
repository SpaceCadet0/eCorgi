import Foundation

/// Сидит. Из этого состояния чаще всего уходит в сон.
final class SitState: BehaviorState {
    let id: BehaviorID = .sit

    func enter(_ pet: Pet) {
        pet.velocity = .zero
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        pet.animator.play(.sit, fps: pet.tuning.idleFPS * 0.6)
        return .stay
    }
}
