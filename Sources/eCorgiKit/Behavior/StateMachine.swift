import Foundation

/// Конечный автомат поведений: держит текущее состояние, его таймер
/// и выбирает следующее по таблице весов из `behaviors.json`.
public final class StateMachine {

    public private(set) var current: BehaviorState
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var plannedDuration: TimeInterval = 0

    private let config: BehaviorConfig
    private let states: [BehaviorID: BehaviorState]
    private let random: RandomSource

    public init(config: BehaviorConfig,
                states: [BehaviorID: BehaviorState],
                initial: BehaviorID = .idle,
                random: RandomSource = .system) {
        self.config = config
        self.states = states
        self.random = random
        self.current = states[initial] ?? states.values.first!
        self.plannedDuration = StateMachine.duration(for: self.current.id, config: config, random: random)
    }

    public func update(_ pet: Pet, dt: TimeInterval) {
        elapsed += dt

        switch current.update(pet, dt: dt) {
        case .switchTo(let id):
            transition(to: id, pet: pet)
        case .done:
            transition(to: pickNext(after: current.id, pet: pet), pet: pet)
        case .stay:
            if current.isInterruptibleByTimer, elapsed >= plannedDuration {
                transition(to: pickNext(after: current.id, pet: pet), pet: pet)
            }
        }
    }

    /// Принудительный переход извне (перетаскивание, падение, команда из меню).
    public func force(_ id: BehaviorID, pet: Pet) {
        guard id != current.id else { return }
        transition(to: id, pet: pet)
    }

    private func transition(to id: BehaviorID, pet: Pet) {
        guard let next = states[id] else { return }
        current.exit(pet)
        current = next
        elapsed = 0
        plannedDuration = StateMachine.duration(for: id, config: config, random: random)
        next.enter(pet)
    }

    // MARK: - Выбор следующего состояния

    func pickNext(after id: BehaviorID, pet: Pet) -> BehaviorID {
        let rules = (config.states[id]?.next ?? []).filter {
            states[$0.state] != nil && $0.weight > 0 && isSatisfied($0.condition, pet: pet)
        }
        guard !rules.isEmpty else { return .idle }

        let total = rules.reduce(0) { $0 + $1.weight }
        var roll = random.unit() * total
        for rule in rules {
            roll -= rule.weight
            if roll < 0 { return rule.state }
        }
        return rules[rules.count - 1].state
    }

    func isSatisfied(_ condition: BehaviorCondition, pet: Pet) -> Bool {
        switch condition {
        case .always:        return true
        case .onGround:      return pet.support != nil
        case .onWindowLedge: return pet.support?.kind == .windowTop
        case .rested:        return pet.timeSinceMoved > 12
        case .nearWall:      return pet.climbableWall() != nil
        case .atLedgeEdge:   return pet.hangAnchorAtEdge() != nil
        case .canJumpDown:   return pet.jumpDownAnchor() != nil
        case .energetic:     return pet.activeTime < pet.tuning.sleepAfterActivity / 2
        }
    }

    private static func duration(for id: BehaviorID, config: BehaviorConfig, random: RandomSource) -> TimeInterval {
        guard let definition = config.states[id] else { return 2 }
        return definition.duration(using: random)
    }
}
