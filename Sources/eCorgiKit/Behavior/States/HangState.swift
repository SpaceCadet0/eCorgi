import Foundation

/// Питомец свесился с края верхней грани окна и покачивается на лапах.
/// Заканчивает сам: либо подтягивается обратно, либо разжимает лапы.
final class HangState: BehaviorState {
    let id: BehaviorID = .hang
    /// Длительность держим внутри состояния — от неё зависит, чем оно кончится.
    let isInterruptibleByTimer = false

    private var elapsed: TimeInterval = 0
    private var plannedDuration: TimeInterval = 0

    func enter(_ pet: Pet) {
        if pet.hangAnchor == nil { pet.hangAnchor = pet.hangAnchorAtEdge() }
        pet.velocity = .zero
        elapsed = 0
        plannedDuration = pet.random.value(in: pet.tuning.hangMinDuration...pet.tuning.hangMaxDuration)
        pet.animator.play(.hang, fps: 6)
    }

    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition {
        // Окно закрылось или уехало — держаться больше не за что.
        guard let anchor = pet.refreshedHangAnchor() else { return .switchTo(.fall) }

        pet.animator.play(.hang, fps: 6)
        elapsed += dt

        // Тело висит под точкой захвата, мордой к окну.
        pet.facing = anchor.side.facing
        pet.position = CGPoint(x: pet.bodyX(besideEdgeAt: anchor.x, side: anchor.side),
                               y: anchor.y - pet.spriteHeight)
        pet.sway = swayAngle(at: elapsed, tuning: pet.tuning)

        guard elapsed >= plannedDuration else { return .stay }
        return pet.random.chance(pet.tuning.hangPullUpChance) ? pullUp(pet, anchor: anchor) : letGo(pet)
    }

    /// Затухающее покачивание: сильнее всего сразу после захвата.
    private func swayAngle(at time: TimeInterval, tuning: BehaviorTuning) -> CGFloat {
        let decay = CGFloat(exp(-time / 4))
        let phase = 2 * Double.pi * time / tuning.hangSwayPeriod
        return tuning.hangSwayAmplitude * decay * CGFloat(sin(phase))
    }

    /// Подтянулся на полку. Переступает вглубь дальше, чем зона захвата края:
    /// иначе он тут же снова оказывается «у края» и залипает в цикле
    /// «повис — подтянулся — повис».
    private func pullUp(_ pet: Pet, anchor: HangAnchor) -> BehaviorTransition {
        let inward = -anchor.side.outward * (Pet.edgeGrabDistance + pet.wallHugOffset)
        var x = anchor.x + inward
        if let ledge = pet.environment.ledges.first(where: {
            $0.kind == .windowTop && abs($0.y - anchor.y) <= 8 && $0.contains(x: anchor.x, tolerance: 2)
        }) {
            x = ledge.clampX(x)
        }
        pet.position = CGPoint(x: x, y: anchor.y)
        pet.facing = anchor.side.facing
        return .switchTo(.land)
    }

    private func letGo(_ pet: Pet) -> BehaviorTransition {
        pet.velocity = .zero
        return .switchTo(.fall)
    }

    func exit(_ pet: Pet) {
        pet.sway = 0
        pet.hangAnchor = nil
    }
}
