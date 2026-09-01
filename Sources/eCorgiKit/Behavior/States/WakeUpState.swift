import Foundation

/// Пробуждение: питомец поднимается после сна.
///
/// Единственный выход из `sleep` по таблице весов. Исключения — испуг и
/// перетаскивание: если рядом оказался курсор или питомца схватили мышью,
/// режиссёр будит его сразу, без потягиваний.
///
/// Кадров у этого действия своих нет — берутся кадры `stand_up`.
final class WakeUpState: BehaviorState {
    let id: BehaviorID = .wakeUp

    func enter(_ pet: Pet) {
        pet.velocity = .zero
        pet.animator.play(.standUp, fps: 8, loops: false)
        pet.animator.restart()
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        pet.animator.play(.standUp, fps: 8, loops: false)
        return .stay
    }
}
