import Foundation

/// Подготовка ко сну: питомец укладывается.
///
/// Короткий переход, без которого сон наступал рывком — только что шёл и
/// вдруг спит. Через это состояние проходят все пути в сон: и «задремал от
/// скуки» по таблице весов, и «набегался» от режиссёра.
///
/// Кадров у этого действия своих нет — берутся кадры `sit_down`, они по
/// смыслу ровно про это (см. раздел 3 в PLAN.md).
final class SettleDownState: BehaviorState {
    let id: BehaviorID = .settleDown
    let spriteAction: SpriteAction = .sitDown
    let previewFPS: Double = 8

    /// Переход длится ровно столько, сколько его анимация: таймер из конфига
    /// обрывал её на полпути при медленном темпе и держал последний кадр при
    /// быстром. Таймер остаётся страховкой для пака с единственным кадром.
    private var playsToEnd = false
    var isInterruptibleByTimer: Bool { !playsToEnd }

    func enter(_ pet: Pet) {
        pet.velocity = .zero
        pet.animator.play(spriteAction, fps: 8, loops: false)
        pet.animator.restart()
        playsToEnd = pet.animator.frameCount > 1
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        pet.animator.play(spriteAction, fps: 8, loops: false)
        return playsToEnd && pet.animator.isFinished ? .done : .stay
    }
}
