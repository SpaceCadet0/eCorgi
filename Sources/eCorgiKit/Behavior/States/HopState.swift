import Foundation

/// Подскок — игривое поведение «от избытка сил».
///
/// Обычная баллистика: толчок вверх и вперёд, дальше всё решает гравитация.
/// Горизонтальная скорость не задаётся отдельной ручкой, а считается из
/// дальности: сколько своих длин нужно перелететь и сколько питомец пробудет
/// в воздухе при заданной высоте толчка. Так дуга остаётся правдоподобной,
/// какой бы ни выставили высоту.
final class HopState: BehaviorState {
    let id: BehaviorID = .hop
    let spriteAction: SpriteAction = .jump
    let previewFPS: Double = 12
    /// Кончается приземлением, а не таймером автомата.
    let isInterruptibleByTimer = false

    /// Темп, при котором цикл укладывается ровно в полёт. Считается на
    /// толчке и держится здесь: `play` на каждом тике иначе сбрасывал бы его.
    private var flightFPS: Double = 12

    func enter(_ pet: Pet) {
        // Оттолкнуться можно только от опоры.
        guard pet.support != nil else { return }

        let up = pet.tuning.hopSpeed * pet.speedFactor
        // Время полёта до возвращения на ту же высоту.
        let flight = 2 * up / PhysicsHelper.gravity
        let distance = pet.spriteWidth * pet.tuning.hopLengths
        let forward = flight > 0 ? distance / flight * pet.facing : 0
        pet.velocity = CGVector(dx: forward, dy: up)
        pet.animator.play(spriteAction, fps: previewFPS, loops: false)
        pet.animator.restart()
        // Все кадры прыжка должны успеть показаться за время полёта.
        flightFPS = pet.animator.fitCycle(into: flight / pet.settings.speedMultiplier)
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        // Оттолкнуться не удалось (опоры не было) — просто возвращаемся к жизни.
        guard pet.velocity.dy != 0 || pet.support == nil else { return .switchTo(.idle) }

        pet.animator.play(spriteAction, fps: flightFPS, loops: false)

        let step = PhysicsHelper.advanceThroughAir(position: pet.position,
                                                   velocity: pet.velocity,
                                                   dt: CGFloat(dt),
                                                   in: pet.environment.ledges)
        pet.position = step.position
        pet.velocity = step.velocity
        // Приземление не разыгрывается отдельным состоянием: подскок слишком
        // лёгкий для этого. Куда идти дальше, решает таблица переходов.
        return step.landing == nil ? .stay : .done
    }
}
