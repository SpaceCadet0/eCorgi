import Foundation

/// Питомца тащит мышь. Позиция догоняет курсор с пружинным запаздыванием —
/// без него спрайт «прилипает» к курсору и выглядит неживым.
final class DragState: BehaviorState {
    let id: BehaviorID = .drag
    let spriteAction: SpriteAction = .drag
    let previewFPS: Double = 8
    /// Первый проход показывает, как питомца подхватили, а дальше он просто
    /// болтает лапами — за это отвечают два последних кадра.
    let animationTail: Int = 2
    /// Выход отсюда — только по отпусканию кнопки мыши (см. Pet.applyDirectorOverrides).
    let isInterruptibleByTimer = false

    func enter(_ pet: Pet) {
        pet.animator.play(spriteAction, fps: 8, tail: animationTail)
        pet.velocity = .zero
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        pet.animator.play(spriteAction, fps: 8, tail: animationTail)

        let target = pet.dragTarget
        let stiffness = min(pet.tuning.dragFollowStiffness * CGFloat(dt), 1)
        let previous = pet.position

        pet.position.x += (target.x - pet.position.x) * stiffness
        pet.position.y += (target.y - pet.position.y) * stiffness

        // Запоминаем скорость руки — она станет начальной скоростью броска.
        if dt > 0 {
            pet.velocity = CGVector(dx: (pet.position.x - previous.x) / CGFloat(dt),
                                    dy: (pet.position.y - previous.y) / CGFloat(dt))
        }
        // Разворачиваем мордой по направлению движения.
        if abs(pet.velocity.dx) > 20 { pet.facing = pet.velocity.dx > 0 ? 1 : -1 }

        return .stay
    }
}
