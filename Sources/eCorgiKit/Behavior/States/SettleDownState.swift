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

    func enter(_ pet: Pet) {
        pet.velocity = .zero
        pet.animator.play(spriteAction, fps: 8, loops: false)
        pet.animator.restart()
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        pet.animator.play(spriteAction, fps: 8, loops: false)
        return .stay
    }
}
