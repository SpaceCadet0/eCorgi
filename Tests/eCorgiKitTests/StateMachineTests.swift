import XCTest
@testable import eCorgiKit

final class StateMachineTests: XCTestCase {

    /// Питомец на фиксированном полу — без обращения к реальным экранам и окнам.
    private func makePet(random: RandomSource = .fixed([0.5])) -> Pet {
        let ground = Ledge(y: 0, minX: 0, maxX: 1000, kind: .ground)
        let environment = ScreenEnvironment(fixedLedges: [ground],
                                            worldBounds: CGRect(x: 0, y: 0, width: 1000, height: 800))
        return Pet(atlas: SpriteAtlas(),
                   environment: environment,
                   settings: .testStore(),
                   random: random,
                   position: CGPoint(x: 500, y: 0))
    }

    private func makeMachine(config: BehaviorConfig, random: RandomSource, initial: BehaviorID = .idle) -> StateMachine {
        StateMachine(config: config, states: Pet.makeStates(), initial: initial, random: random)
    }

    func testWeightedPickRespectsBuckets() {
        let config = BehaviorConfig(states: [
            .idle: BehaviorDefinition(minDuration: 1, maxDuration: 1, next: [
                BehaviorTransitionRule(state: .walk, weight: 25),
                BehaviorTransitionRule(state: .sit, weight: 75)
            ])
        ])
        let pet = makePet()

        // Первая четверть диапазона весов — walk, остальное — sit.
        XCTAssertEqual(makeMachine(config: config, random: .fixed([0.1])).pickNext(after: .idle, pet: pet), .walk)
        XCTAssertEqual(makeMachine(config: config, random: .fixed([0.9])).pickNext(after: .idle, pet: pet), .sit)
    }

    func testUnsatisfiedConditionExcludesRule() {
        let config = BehaviorConfig(states: [
            .idle: BehaviorDefinition(minDuration: 1, maxDuration: 1, next: [
                // Условие не выполнено: питомец стоит на полу, а не на окне.
                BehaviorTransitionRule(state: .sleep, weight: 1000, condition: .onWindowLedge),
                BehaviorTransitionRule(state: .walk, weight: 1)
            ])
        ])
        let pet = makePet()
        pet.update(0)  // проставить опору

        let machine = makeMachine(config: config, random: .fixed([0.99]))
        XCTAssertEqual(machine.pickNext(after: .idle, pet: pet), .walk)
    }

    func testFallbackToIdleWhenNoRuleApplies() {
        let config = BehaviorConfig(states: [
            .walk: BehaviorDefinition(minDuration: 1, maxDuration: 1, next: [])
        ])
        XCTAssertEqual(makeMachine(config: config, random: .fixed([0.5])).pickNext(after: .walk, pet: makePet()), .idle)
    }

    func testTimerSwitchesInterruptibleState() {
        let config = BehaviorConfig(states: [
            .idle: BehaviorDefinition(minDuration: 0.5, maxDuration: 0.5, next: [
                BehaviorTransitionRule(state: .sit, weight: 1)
            ]),
            .sit: BehaviorDefinition(minDuration: 10, maxDuration: 10, next: [])
        ])
        let pet = makePet()
        let machine = makeMachine(config: config, random: .fixed([0.5]))

        machine.update(pet, dt: 0.3)
        XCTAssertEqual(machine.current.id, .idle, "Таймер ещё не истёк")
        machine.update(pet, dt: 0.3)
        XCTAssertEqual(machine.current.id, .sit)
    }

    func testDragAndFallIgnoreTheTimer() {
        for id in [BehaviorID.drag, .fall] {
            let state = Pet.makeStates()[id]
            XCTAssertEqual(state?.isInterruptibleByTimer, false,
                           "\(id.rawValue) должен заканчиваться событием, а не таймером")
        }
    }

    func testBundledConfigCoversEveryBehaviour() {
        let config = BehaviorConfig.load()
        for id in BehaviorID.allCases {
            XCTAssertNotNil(config.states[id], "В behaviors.json нет состояния \(id.rawValue)")
        }
        // Все цели переходов должны существовать — иначе автомат молча упрётся в idle.
        for (id, definition) in config.states {
            for rule in definition.next {
                XCTAssertNotNil(config.states[rule.state],
                                "\(id.rawValue) ссылается на неизвестное состояние \(rule.state.rawValue)")
            }
        }
    }
}

final class PetBehaviourTests: XCTestCase {

    private func makePet(ledges: [Ledge], at position: CGPoint) -> Pet {
        let environment = ScreenEnvironment(fixedLedges: ledges,
                                            worldBounds: CGRect(x: 0, y: 0, width: 1000, height: 800))
        return Pet(atlas: SpriteAtlas(),
                   environment: environment,
                   settings: .testStore(),
                   random: .fixed([0.5]),
                   position: position)
    }

    func testPetWithoutSupportStartsFalling() {
        let pet = makePet(ledges: [Ledge(y: 0, minX: 0, maxX: 1000, kind: .ground)],
                          at: CGPoint(x: 500, y: 400))
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.currentBehavior, .fall)
    }

    func testFallingPetLandsOnTheGround() {
        let pet = makePet(ledges: [Ledge(y: 0, minX: 0, maxX: 1000, kind: .ground)],
                          at: CGPoint(x: 500, y: 400))
        for _ in 0..<120 { pet.update(1.0 / 30) }
        XCTAssertEqual(pet.position.y, 0, accuracy: 0.001)
        XCTAssertNotEqual(pet.currentBehavior, .fall, "После приземления падение должно закончиться")
    }

    func testPetLandsOnWindowLedgeAboveTheGround() {
        let ledges = [
            Ledge(y: 0, minX: 0, maxX: 1000, kind: .ground),
            Ledge(y: 200, minX: 400, maxX: 700, kind: .windowTop)
        ]
        let pet = makePet(ledges: ledges, at: CGPoint(x: 500, y: 600))
        for _ in 0..<60 { pet.update(1.0 / 30) }
        XCTAssertEqual(pet.position.y, 200, accuracy: 0.001)
        XCTAssertEqual(pet.support?.kind, .windowTop)
    }

    func testDraggedPetFollowsTheCursorAndFallsOnRelease() {
        let pet = makePet(ledges: [Ledge(y: 0, minX: 0, maxX: 1000, kind: .ground)],
                          at: CGPoint(x: 500, y: 0))
        pet.isDragged = true
        pet.dragTarget = CGPoint(x: 500, y: 500)
        for _ in 0..<30 { pet.update(1.0 / 30) }

        XCTAssertEqual(pet.currentBehavior, .drag)
        XCTAssertGreaterThan(pet.position.y, 100, "Питомец должен тянуться к курсору")

        pet.isDragged = false
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.currentBehavior, .fall)
    }
}

final class BehaviorConfigTests: XCTestCase {

    private func decode(_ json: String) throws -> BehaviorConfig {
        try JSONDecoder().decode(BehaviorConfig.self, from: Data(json.utf8))
    }

    func testMissingTuningFieldsKeepTheirDefaults() throws {
        // Правка behaviors.json не должна требовать перечислять всё подряд.
        let config = try decode("""
        { "tuning": { "walkSpeed": 99 },
          "states": { "idle": { "minDuration": 1, "maxDuration": 2, "next": [] } } }
        """)
        XCTAssertEqual(config.tuning.walkSpeed, 99)
        XCTAssertEqual(config.tuning.climbSpeed, BehaviorTuning().climbSpeed)
        XCTAssertEqual(config.tuning.hangPullUpChance, BehaviorTuning().hangPullUpChance)
    }

    func testUnknownTuningKeysAreIgnored() throws {
        let config = try decode("""
        { "tuning": { "walkSpeed": 42, "somethingFromTheFuture": 7 }, "states": {} }
        """)
        XCTAssertEqual(config.tuning.walkSpeed, 42)
    }

    func testSleepIsAlwaysWrappedInItsTransitions() {
        // Инвариант: в сон входят только через укладывание, а выходят только
        // через пробуждение. Иначе новый переход легко проскочит мимо них.
        let config = BehaviorConfig.load()

        let leadingToSleep = config.states
            .filter { $0.value.next.contains { $0.state == .sleep } }
            .map(\.key)
        XCTAssertEqual(leadingToSleep, [.settleDown], "В сон ведёт только подготовка ко сну")

        let leavingSleep = config.states[.sleep]?.next.map(\.state)
        XCTAssertEqual(leavingSleep, [.wakeUp], "Из сна ведёт только пробуждение")
    }

    func testBundledConfigActuallyParsesRatherThanFallingBack() {
        // Самая коварная поломка: новое поле в BehaviorTuning без ключа в JSON
        // роняло разбор целиком, и приложение молча уезжало на запасной конфиг.
        let config = BehaviorConfig.load()
        XCTAssertGreaterThan(config.states.count, BehaviorConfig.fallback.states.count,
                             "Загрузился встроенный запасной конфиг вместо behaviors.json")
        XCTAssertEqual(config.tuning.climbSpeed, 110, "Значения tuning должны приходить из JSON")
    }
}
