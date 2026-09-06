import Foundation

/// Спрыгивание с края верхней грани окна вниз.
///
/// Траектория честно баллистическая: толчок наружу и вверх, дальше только
/// гравитация. Скорость отталкивания фиксированная и под цель не
/// подгоняется — поэтому питомец может перелететь нижнюю полку и
/// приземлиться этажом ниже. Приземление ловится по любой полке на пути.
final class JumpDownState: BehaviorState {
    let id: BehaviorID = .jumpDown
    let spriteAction: SpriteAction = .jump
    let previewFPS: Double = 12
    /// Кончается приземлением, а не таймером автомата.
    let isInterruptibleByTimer = false

    /// Взлетел ли питомец. Если край найти не удалось — состояние
    /// само себя отменяет, а не роняет питомца на ровном месте.
    private var launched = false

    func enter(_ pet: Pet) {
        launched = false
        guard let anchor = pet.jumpDownAnchor() else { return }

        let outward = anchor.side.outward
        pet.facing = outward
        pet.velocity = CGVector(dx: pet.tuning.jumpSpeed * pet.speedFactor * outward,
                                dy: pet.tuning.jumpLift * pet.speedFactor)
        // Чуть за край, чтобы сразу оторваться от полки, а не зацепиться за неё.
        pet.position.x = anchor.x + outward * 2
        pet.animator.play(spriteAction, fps: 12, loops: false)
        pet.animator.restart()
        launched = true
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        guard launched else {
            return pet.support == nil ? .switchTo(.fall) : .switchTo(.idle)
        }
        pet.animator.play(spriteAction, fps: 12, loops: false)

        let step = PhysicsHelper.advanceThroughAir(position: pet.position,
                                                   velocity: pet.velocity,
                                                   dt: CGFloat(dt),
                                                   airDrag: pet.tuning.jumpAirDrag,
                                                   in: pet.environment.ledges)
        pet.position = step.position
        pet.velocity = step.velocity
        return step.landing == nil ? .stay : .switchTo(.land)
    }
}
