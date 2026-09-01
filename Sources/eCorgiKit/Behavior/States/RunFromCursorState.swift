import Foundation

/// Убегает от курсора — фирменная реакция оригинального eSheep.
/// Заканчивается, когда мышь отошла достаточно далеко или упёрся в край полки.
final class RunFromCursorState: BehaviorState {
    let id: BehaviorID = .runFromCursor

    private let edgeMargin: CGFloat = 4

    func enter(_ pet: Pet) {
        // Бежим в сторону, противоположную курсору.
        pet.facing = pet.cursor.location.x > pet.position.x ? -1 : 1
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        guard let ledge = pet.walkableLedge() else { return .switchTo(.fall) }

        pet.animator.play(.run, fps: pet.tuning.runFPS)

        let step = pet.tuning.runSpeed * pet.speedFactor * CGFloat(dt) * pet.facing
        let nextX = pet.position.x + step

        if nextX < ledge.minX + edgeMargin || nextX > ledge.maxX - edgeMargin {
            // Загнали в угол — дальше бежать некуда, разворачиваемся и успокаиваемся.
            pet.position.x = ledge.clampX(nextX)
            pet.facing *= -1
            return .done
        }

        pet.position.x = nextX
        pet.position.y = ledge.y

        let bodyCentre = CGPoint(x: pet.position.x, y: pet.position.y + pet.spriteHeightHint / 2)
        return pet.cursor.distance(to: bodyCentre) > pet.tuning.cursorCalmRadius ? .done : .stay
    }
}
