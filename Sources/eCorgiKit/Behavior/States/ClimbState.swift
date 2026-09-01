import Foundation

/// Подъём по вертикальной грани окна. Питомец цепляется за грань снаружи
/// и лезет вверх, пока не переступит на верхнюю грань этого же окна.
final class ClimbState: BehaviorState {
    let id: BehaviorID = .climb
    /// Лазание заканчивается вершиной или сорвавшейся опорой, а не таймером.
    let isInterruptibleByTimer = false

    func enter(_ pet: Pet) {
        // Состояние могло быть выбрано и таблицей переходов — тогда цель ищем сами.
        if pet.climbTarget == nil { pet.climbTarget = pet.climbableWall() }
        pet.velocity = .zero
        if let wall = pet.climbTarget { pet.facing = wall.side.facing }
        pet.animator.play(.climb, fps: 10)
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        // Окно могло уехать или закрыться — грань переискиваем каждый тик.
        guard let wall = pet.refreshedClimbTarget() else {
            // Не за что держаться. Если под лапами есть пол — просто отменяем
            // затею, иначе честно падаем.
            return pet.support == nil ? .switchTo(.fall) : .switchTo(.idle)
        }

        pet.animator.play(.climb, fps: 10)
        pet.facing = wall.side.facing
        pet.position.x = pet.bodyX(besideEdgeAt: wall.x, side: wall.side)
        pet.position.y += pet.tuning.climbSpeed * pet.speedFactor * CGFloat(dt)

        guard pet.position.y >= wall.maxY else { return .stay }
        return stepOntoTop(of: wall, pet: pet)
    }

    /// Переступаем с грани на верх окна.
    private func stepOntoTop(of wall: Wall, pet: Pet) -> BehaviorTransition {
        let landingX = wall.x - wall.side.outward * pet.ledgeStepInset
        let top = pet.environment.ledges.first {
            abs($0.y - wall.maxY) <= 4 && $0.contains(x: landingX, tolerance: pet.ledgeStepInset)
        }
        guard let top else {
            // Верхнюю грань перекрыло чужое окно — держаться наверху не за что.
            pet.position.y = wall.maxY
            return .switchTo(.fall)
        }
        pet.position = CGPoint(x: top.clampX(landingX), y: top.y)
        pet.velocity = .zero
        return .switchTo(.land)
    }

    func exit(_ pet: Pet) {
        pet.climbTarget = nil
    }
}
