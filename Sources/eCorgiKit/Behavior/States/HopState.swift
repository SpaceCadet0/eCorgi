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
    let spriteAction: SpriteAction = .hop
    let previewFPS: Double = 12
    /// Кончается приземлением, а не таймером автомата.
    let isInterruptibleByTimer = false

    /// Темп анимации и гравитация этого подскока. Считаются на толчке и
    /// держатся здесь: `play` на каждом тике иначе сбрасывал бы темп.
    private var flightFPS: Double = 15
    private var hopGravity: CGFloat = PhysicsHelper.gravity

    func enter(_ pet: Pet) {
        // Оттолкнуться можно только от опоры.
        guard pet.support != nil else { return }

        // Подскок длится ровно один цикл кадров: так анимация всегда успевает
        // пройти целиком при любой высоте. Из высоты h и времени полёта T
        // следуют скорость толчка 4h/T и своя гравитация 8h/T² — общая
        // гравитация при низком подскоке дала бы полёт короче анимации.
        pet.animator.play(spriteAction, fps: pet.tuning.hopFPS, loops: false)
        pet.animator.restart()
        let frames = Double(max(pet.animator.frameCount, 1))
        let flight = CGFloat(frames / max(pet.tuning.hopFPS, 1)) / pet.speedFactor
        let height = max(pet.tuning.hopHeight, 0)
        let up = 4 * height / flight
        hopGravity = 8 * height / (flight * flight)

        let distance = pet.spriteWidth * pet.tuning.hopLengths
        pet.velocity = CGVector(dx: distance / flight * pet.facing, dy: up)
        // Аниматор сам ускоряется настройкой скорости, поэтому цикл
        // подгоняется под полёт в его собственном времени. Иначе при
        // скорости 2× анимация кончалась на середине дуги.
        flightFPS = pet.animator.fitCycle(into: TimeInterval(flight * pet.speedFactor))
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        // Оттолкнуться не удалось (опоры не было) — просто возвращаемся к жизни.
        guard pet.velocity.dy != 0 || pet.support == nil else { return .switchTo(.idle) }

        pet.animator.play(spriteAction, fps: flightFPS, loops: false)

        let step = PhysicsHelper.advanceThroughAir(position: pet.position,
                                                   velocity: pet.velocity,
                                                   dt: CGFloat(dt),
                                                   gravity: hopGravity,
                                                   in: pet.environment.ledges)
        pet.position = step.position
        pet.velocity = step.velocity
        // Приземление не разыгрывается отдельным состоянием: подскок слишком
        // лёгкий для этого. Куда идти дальше, решает таблица переходов.
        return step.landing == nil ? .stay : .done
    }
}
