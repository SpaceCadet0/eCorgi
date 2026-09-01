import XCTest
@testable import eCorgiKit

/// Сон по накопленной усталости: питомец укладывается спать, набегав
/// заданное время деятельных состояний.
final class TirednessTests: XCTestCase {

    private static let ground = Ledge(y: 0, minX: 0, maxX: 1200, kind: .ground)
    private static let windowTop = Ledge(y: 400, minX: 500, maxX: 800, kind: .windowTop)
    private static let wall = Wall(x: 500, minY: 40, maxY: 400, side: .left)

    /// Конфиг без единого перехода в сон по весам: так единственной причиной
    /// заснуть остаётся усталость, и тест меряет именно её.
    private func config(threshold: TimeInterval) -> BehaviorConfig {
        var tuning = BehaviorTuning()
        tuning.sleepAfterActivity = threshold
        tuning.seekWallChance = 0
        tuning.climbChance = 0

        func rule(_ state: BehaviorID) -> BehaviorTransitionRule {
            BehaviorTransitionRule(state: state, weight: 1)
        }
        return BehaviorConfig(states: [
            .idle:  BehaviorDefinition(minDuration: 0.5, maxDuration: 0.5, next: [rule(.walk)]),
            .walk:  BehaviorDefinition(minDuration: 2.0, maxDuration: 2.0, next: [rule(.idle)]),
            .sit:   BehaviorDefinition(minDuration: 999, maxDuration: 999, next: [rule(.idle)]),
            // Путь в сон и обратно всегда идёт через переходные состояния.
            .settleDown: BehaviorDefinition(minDuration: 0.5, maxDuration: 0.5, next: [rule(.sleep)]),
            .sleep: BehaviorDefinition(minDuration: 999, maxDuration: 999, next: [rule(.wakeUp)]),
            .wakeUp: BehaviorDefinition(minDuration: 0.5, maxDuration: 0.5, next: [rule(.idle)]),
            .land:  BehaviorDefinition(minDuration: 0.3, maxDuration: 0.3, next: [rule(.idle)]),
            .fall:  BehaviorDefinition(minDuration: 999, maxDuration: 999, next: [rule(.idle)]),
            .climb: BehaviorDefinition(minDuration: 999, maxDuration: 999, next: [rule(.land)]),
            .hang:  BehaviorDefinition(minDuration: 999, maxDuration: 999, next: [rule(.land)])
        ], tuning: tuning)
    }

    private func makePet(threshold: TimeInterval,
                         ledges: [Ledge] = [TirednessTests.ground, TirednessTests.windowTop],
                         walls: [Wall] = [TirednessTests.wall],
                         at position: CGPoint = CGPoint(x: 300, y: 0)) -> Pet {
        let environment = ScreenEnvironment(fixedLedges: ledges,
                                            fixedWalls: walls,
                                            worldBounds: CGRect(x: 0, y: 0, width: 1200, height: 900))
        return Pet(atlas: SpriteAtlas(),
                   environment: environment,
                   settings: .testStore(),
                   config: config(threshold: threshold),
                   random: .fixed([0.5]),
                   position: position)
    }

    /// Гоняет тик, пока питомец не заснёт. Возвращает набеганную к тому
    /// моменту активность и сколько секунд заняло по «часам».
    private func runUntilAsleep(_ pet: Pet, limit: TimeInterval = 400) -> (activity: TimeInterval, elapsed: TimeInterval)? {
        let dt = 1.0 / 30
        var elapsed: TimeInterval = 0
        var lastActivity: TimeInterval = 0
        while elapsed < limit {
            lastActivity = pet.activeTime
            pet.update(dt)
            elapsed += dt
            if pet.currentBehavior == .sleep { return (lastActivity, elapsed) }
        }
        return nil
    }

    // MARK: - Основной сценарий

    func testPetFallsAsleepAfterEnoughActivity() {
        let threshold: TimeInterval = 20
        let pet = makePet(threshold: threshold)
        pet.force(.walk)

        guard let result = runUntilAsleep(pet) else {
            return XCTFail("Питомец так и не уснул")
        }
        XCTAssertGreaterThanOrEqual(result.activity, threshold - 0.05,
                                    "Заснул раньше, чем набегал положенное")
        XCTAssertLessThan(result.activity, threshold + 0.2,
                          "Заснул заметно позже порога")
        XCTAssertGreaterThan(result.elapsed, threshold,
                             "По часам должно пройти больше: паузы в активность не идут")
    }

    func testStandingAndSittingDoNotMakeThePetTired() {
        let pet = makePet(threshold: 5)
        pet.force(.sit)

        for _ in 0..<(30 * 60) { pet.update(1.0 / 30) }   // минута сидения

        XCTAssertEqual(pet.activeTime, 0, accuracy: 0.001, "Сидение — это отдых, а не активность")
        XCTAssertFalse(pet.isTired)
        XCTAssertEqual(pet.currentBehavior, .sit)
    }

    func testSleepClearsTheTiredness() {
        let pet = makePet(threshold: 10)
        pet.force(.walk)
        XCTAssertNotNil(runUntilAsleep(pet), "Питомец должен был уснуть")

        XCTAssertEqual(pet.activeTime, 0, accuracy: 0.001)
        XCTAssertFalse(pet.isTired)
    }

    func testShortNapFromBoredomKeepsTheAccumulatedTiredness() {
        // Ключевой момент: без этого старое правило «задремать от скуки»
        // обнуляло бы счётчик раньше порога, и сон по усталости не наступал бы.
        let pet = makePet(threshold: 999)
        pet.force(.walk)
        for _ in 0..<300 { pet.update(1.0 / 30) }
        let before = pet.activeTime
        XCTAssertGreaterThan(before, 7, "За 10 с автомат чередует ходьбу и простой")

        pet.force(.sleep)
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.activeTime, before, accuracy: 0.05,
                       "Дрёма не от усталости не должна списывать накопленное")
    }

    func testTirednessAccumulatesOnlyWhileActive() {
        let pet = makePet(threshold: 999)
        pet.force(.walk)
        for _ in 0..<30 { pet.update(1.0 / 30) }
        let afterWalking = pet.activeTime
        XCTAssertEqual(afterWalking, 1, accuracy: 0.05)

        // Именно sit: у idle в этом конфиге короткая длительность, и автомат
        // сам увёл бы питомца обратно в ходьбу.
        pet.force(.sit)
        for _ in 0..<60 { pet.update(1.0 / 30) }
        XCTAssertEqual(pet.activeTime, afterWalking, accuracy: 0.05, "Отдых не должен утомлять")
    }

    // MARK: - Откуда засыпать нельзя

    func testTiredPetDoesNotFallAsleepInMidAir() {
        let pet = makePet(threshold: 0.1, at: CGPoint(x: 300, y: 600))
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.currentBehavior, .fall)

        for _ in 0..<10 { pet.update(1.0 / 30) }
        XCTAssertTrue(pet.isTired, "Падение — тоже активность")
        XCTAssertEqual(pet.currentBehavior, .fall, "В воздухе заснуть нельзя")

        // Приземлившись, укладывается и засыпает.
        for _ in 0..<300 { pet.update(1.0 / 30) }
        XCTAssertEqual(pet.currentBehavior, .sleep)
        XCTAssertEqual(pet.position.y, 0, accuracy: 0.001)
    }

    func testTiredPetDoesNotFallAsleepMidClimb() {
        let pet = makePet(threshold: 0.1, at: CGPoint(x: 495, y: 0))
        pet.update(0)
        pet.climbTarget = TirednessTests.wall
        pet.force(.climb)

        for _ in 0..<30 { pet.update(1.0 / 30) }
        XCTAssertTrue(pet.isTired)
        XCTAssertEqual(pet.currentBehavior, .climb, "Уснуть на середине грани значило бы сорваться")
        XCTAssertGreaterThan(pet.position.y, 0)
    }

    func testTiredPetDoesNotFallAsleepWhileBeingDragged() {
        let pet = makePet(threshold: 0.1)
        pet.isDragged = true
        pet.dragTarget = CGPoint(x: 400, y: 300)

        for _ in 0..<60 { pet.update(1.0 / 30) }
        XCTAssertTrue(pet.isTired)
        XCTAssertEqual(pet.currentBehavior, .drag, "Пока его держат, спать он не ляжет")
    }

    // MARK: - Прелюдия и пробуждение

    func testTirednessLeadsThroughSettleDownRatherThanStraightToSleep() {
        let pet = makePet(threshold: 0.1)
        pet.force(.walk)
        for _ in 0..<10 { pet.update(1.0 / 30) }

        XCTAssertEqual(pet.currentBehavior, .settleDown, "Сначала укладывается")

        var ticks = 0
        while pet.currentBehavior != .sleep, ticks < 100 { pet.update(1.0 / 30); ticks += 1 }
        XCTAssertEqual(pet.currentBehavior, .sleep, "И только потом засыпает")
    }

    func testSleepIsFollowedByWakingUp() {
        var tuning = BehaviorTuning()
        tuning.sleepAfterActivity = 999
        let config = BehaviorConfig(states: [
            .settleDown: BehaviorDefinition(minDuration: 0.3, maxDuration: 0.3,
                                            next: [BehaviorTransitionRule(state: .sleep, weight: 1)]),
            .sleep: BehaviorDefinition(minDuration: 0.5, maxDuration: 0.5,
                                       next: [BehaviorTransitionRule(state: .wakeUp, weight: 1)]),
            .wakeUp: BehaviorDefinition(minDuration: 0.4, maxDuration: 0.4,
                                        next: [BehaviorTransitionRule(state: .idle, weight: 1)]),
            .idle: BehaviorDefinition(minDuration: 999, maxDuration: 999, next: [])
        ], tuning: tuning)

        let environment = ScreenEnvironment(fixedLedges: [TirednessTests.ground],
                                            worldBounds: CGRect(x: 0, y: 0, width: 1200, height: 900))
        let pet = Pet(atlas: SpriteAtlas(), environment: environment, settings: .testStore(),
                      config: config, random: .fixed([0.5]), position: CGPoint(x: 300, y: 0))
        pet.force(.settleDown)

        var seen: [BehaviorID] = []
        for _ in 0..<120 {
            pet.update(1.0 / 30)
            if seen.last != pet.currentBehavior { seen.append(pet.currentBehavior) }
        }
        XCTAssertEqual(seen, [.settleDown, .sleep, .wakeUp, .idle],
                       "Полный цикл: уложился — поспал — проснулся — вернулся к жизни")
    }

    func testSettlingAndWakingDoNotCountAsActivity() {
        let pet = makePet(threshold: 999)
        pet.force(.settleDown)
        for _ in 0..<10 { pet.update(1.0 / 30) }
        XCTAssertEqual(pet.activeTime, 0, accuracy: 0.001, "Укладывание — это отдых")

        pet.force(.wakeUp)
        for _ in 0..<10 { pet.update(1.0 / 30) }
        XCTAssertEqual(pet.activeTime, 0, accuracy: 0.001, "И пробуждение тоже")
    }

    func testIsAsleepCoversSettlingDown() {
        let pet = makePet(threshold: 999)
        XCTAssertFalse(pet.isAsleep)
        pet.force(.settleDown)
        XCTAssertTrue(pet.isAsleep, "Пункт меню должен предлагать разбудить уже укладывающегося")
        pet.force(.sleep)
        XCTAssertTrue(pet.isAsleep)
        pet.force(.wakeUp)
        XCTAssertFalse(pet.isAsleep)
    }

    // MARK: - Настройка

    func testThresholdComesFromTheBundledConfig() {
        XCTAssertEqual(BehaviorConfig.load().tuning.sleepAfterActivity, 120,
                       "Порог усталости должен настраиваться в behaviors.json")
    }
}
