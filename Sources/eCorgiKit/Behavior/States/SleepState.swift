import Foundation

/// Спит. Просыпается по таймеру или когда его хватают мышью.
final class SleepState: BehaviorState {
    let id: BehaviorID = .sleep

    func enter(_ pet: Pet) {
        pet.velocity = .zero
        pet.recoverFromSleep()
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        pet.animator.play(.sleep, fps: 2.5)
        return .stay
    }
}
