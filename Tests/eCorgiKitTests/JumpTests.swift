import XCTest
@testable import eCorgiKit

/// Мир: пол, окно повыше и промежуточная полка между ними.
private enum JumpScene {
    static let ground = Ledge(y: 0, minX: 0, maxX: 1200, kind: .ground)
    static let window = Ledge(y: 400, minX: 500, maxX: 800, kind: .windowTop)
    /// Полка ниже окна и правее его края — прямо под траекторией прыжка вправо.
    static let shelf = Ledge(y: 250, minX: 810, maxX: 1000, kind: .windowTop)
}

final class JumpTests: XCTestCase {

    private func makePet(ledges: [Ledge] = [JumpScene.ground, JumpScene.window],
                         at position: CGPoint,
                         random: RandomSource = .fixed([0.5])) -> Pet {
        let environment = ScreenEnvironment(fixedLedges: ledges,
                                            worldBounds: CGRect(x: 0, y: 0, width: 1200, height: 900))
        return Pet(atlas: SpriteAtlas(),
                   environment: environment,
                   settings: .testStore(),
                   random: random,
                   position: position)
    }

    @discardableResult
    private func run(_ pet: Pet, whileIn behavior: BehaviorID, maxTicks: Int = 600) -> Int {
        var ticks = 0
        while pet.currentBehavior == behavior, ticks < maxTicks {
            pet.update(1.0 / 30)
            ticks += 1
        }
        return ticks
    }

    // MARK: - Подскок на месте

    func testHopRisesAndComesBackToTheSameSpot() {
        let pet = makePet(at: CGPoint(x: 300, y: 0))
        pet.update(0)
        let startX = pet.position.x
        pet.force(.hop)

        var apex: CGFloat = 0
        var ticks = 0
        while pet.currentBehavior == .hop, ticks < 200 {
            pet.update(1.0 / 30)
            apex = max(apex, pet.position.y)
            ticks += 1
        }

        // Высота считается от настройки, а не пинится числом: hopSpeed —
        // это ручка, её крутят.
        let analytic = pow(pet.tuning.hopSpeed, 2) / (2 * PhysicsHelper.gravity)
        XCTAssertGreaterThan(apex, analytic * 0.4, "Подскок должен быть заметным")
        XCTAssertEqual(pet.position.y, 0, accuracy: 0.001, "И вернуться на ту же полку")
        XCTAssertEqual(pet.position.x, startX, accuracy: 0.001, "Прыжок на месте не сносит вбок")
        XCTAssertEqual(pet.currentBehavior, .land)
    }

    func testHopHeightMatchesTheConfiguredImpulse() {
        let pet = makePet(at: CGPoint(x: 300, y: 0))
        pet.update(0)
        pet.force(.hop)

        var apex: CGFloat = 0
        var ticks = 0
        while pet.currentBehavior == .hop, ticks < 200 {
            pet.update(1.0 / 30)
            apex = max(apex, pet.position.y)
            ticks += 1
        }
        // Аналитическая высота — v² / (2g). Пошаговое интегрирование на 30 fps
        // систематически недобирает до неё, причём тем сильнее, чем слабее
        // импульс: у низкого подскока на весь полёт приходится всего пара
        // тиков. Поэтому проверяем не точное совпадение, а что связь
        // «импульс → высота» не сломана.
        let analytic = pow(pet.tuning.hopSpeed, 2) / (2 * PhysicsHelper.gravity)
        XCTAssertGreaterThan(apex, analytic * 0.4)
        XCTAssertLessThanOrEqual(apex, analytic)
    }

    func testHopIsNotTurnedIntoAFallByTheDirector() {
        let pet = makePet(at: CGPoint(x: 300, y: 0))
        pet.update(0)
        pet.force(.hop)

        for _ in 0..<3 { pet.update(1.0 / 30) }
        XCTAssertNil(pet.support, "В воздухе опоры нет")
        XCTAssertEqual(pet.currentBehavior, .hop, "…но это прыжок, а не падение")
    }

    func testHopWithoutSupportGivesUpInsteadOfLaunching() {
        let pet = makePet(at: CGPoint(x: 300, y: 600))
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.currentBehavior, .fall, "Без опоры питомец падает")
    }

    // MARK: - Спрыгивание с края

    func testJumpDownCarriesThePetOffTheWindowAndOntoTheGround() {
        let pet = makePet(at: CGPoint(x: JumpScene.window.maxX - 5, y: JumpScene.window.y))
        pet.update(0)
        XCTAssertEqual(pet.support?.kind, .windowTop)

        pet.force(.jumpDown)
        run(pet, whileIn: .jumpDown)

        XCTAssertEqual(pet.position.y, JumpScene.ground.y, accuracy: 0.001)
        XCTAssertGreaterThan(pet.position.x, JumpScene.window.maxX,
                             "Прыжок должен унести питомца за край окна, а не уронить вертикально")
        XCTAssertEqual(pet.currentBehavior, .land)
    }

    func testJumpDownStartsWithAnUpwardLift() {
        let pet = makePet(at: CGPoint(x: JumpScene.window.maxX - 5, y: JumpScene.window.y))
        pet.update(0)
        pet.force(.jumpDown)

        var apex: CGFloat = 0
        for _ in 0..<5 {
            pet.update(1.0 / 30)
            apex = max(apex, pet.position.y)
        }
        XCTAssertGreaterThan(apex, JumpScene.window.y,
                             "Сначала подброс вверх — иначе это шаг в пустоту, а не прыжок")
    }

    func testJumpDownLandsOnAnIntermediateLedgeWhenItIsInTheArc() {
        let pet = makePet(ledges: [JumpScene.ground, JumpScene.window, JumpScene.shelf],
                          at: CGPoint(x: JumpScene.window.maxX - 5, y: JumpScene.window.y))
        pet.update(0)
        pet.force(.jumpDown)
        run(pet, whileIn: .jumpDown)

        XCTAssertEqual(pet.position.y, JumpScene.shelf.y, accuracy: 0.001,
                       "Полка на пути должна поймать питомца раньше пола")
    }

    func testJumpDownFacesTheDirectionOfTravel() {
        let right = makePet(at: CGPoint(x: JumpScene.window.maxX - 5, y: JumpScene.window.y))
        right.update(0)
        right.force(.jumpDown)
        right.update(1.0 / 30)
        XCTAssertEqual(right.facing, 1)

        let left = makePet(at: CGPoint(x: JumpScene.window.minX + 5, y: JumpScene.window.y))
        left.update(0)
        left.force(.jumpDown)
        left.update(1.0 / 30)
        XCTAssertEqual(left.facing, -1)
    }

    func testJumpDownFromTheMiddleOfALedgeIsCancelled() {
        let pet = makePet(at: CGPoint(x: 650, y: JumpScene.window.y))
        pet.update(0)
        XCTAssertNil(pet.hangAnchorAtEdge(), "Для чистоты теста — питомец не у края")

        pet.force(.jumpDown)
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.currentBehavior, .idle, "Прыгать неоткуда — состояние отменяет само себя")
        XCTAssertEqual(pet.position.y, JumpScene.window.y, accuracy: 0.001)
    }

    // MARK: - Край экрана

    func testJumpDownIsNotOfferedWhenThereIsNoRoomOutside() {
        // Край окна близко к границе экрана: приземляться после прыжка было
        // бы некуда, иначе вышло бы сползание по стенке.
        //
        // Вплотную к границе питомца не поставить — его удерживает боковой
        // ограничитель, — поэтому край окна отодвинут внутрь ровно настолько,
        // чтобы питомец до него дотянулся, а места для прыжка уже не было.
        let probe = makePet(ledges: [JumpScene.ground], at: CGPoint(x: 600, y: 0))
        let edgeX = 1200 - probe.spriteWidth * 0.6

        let window = Ledge(y: 400, minX: 200, maxX: edgeX, kind: .windowTop)
        let pet = makePet(ledges: [JumpScene.ground, window], at: CGPoint(x: edgeX, y: 400))
        pet.update(0)

        XCTAssertNotNil(pet.hangAnchorAtEdge(), "У края он всё-таки стоит — повиснуть можно")
        XCTAssertNil(pet.jumpDownAnchor(), "…но спрыгивать некуда")
    }

    func testJumpDownCancelsItselfAtTheScreenEdge() {
        let fullWidth = Ledge(y: 400, minX: 0, maxX: 1200, kind: .windowTop)
        let pet = makePet(ledges: [JumpScene.ground, fullWidth],
                          at: CGPoint(x: 1200, y: 400))
        pet.update(0)
        pet.force(.jumpDown)
        pet.update(1.0 / 30)

        XCTAssertEqual(pet.currentBehavior, .idle)
        XCTAssertEqual(pet.position.y, 400, accuracy: 0.001, "И остался стоять на окне")
    }

    func testWalkTurnsAroundInsteadOfJumpingAtTheScreenEdge() {
        let fullWidth = Ledge(y: 400, minX: 0, maxX: 1200, kind: .windowTop)
        let pet = makePet(ledges: [JumpScene.ground, fullWidth],
                          at: CGPoint(x: 1150, y: 400),
                          random: .fixed([0.3]))   // полоса спрыгивания
        pet.update(0)
        pet.force(.walk)
        pet.facing = 1

        var reachedEdge = false
        var leftTheLedge = false
        for _ in 0..<300 {
            pet.update(1.0 / 30)
            if pet.position.x >= pet.walkableSpan(of: fullWidth).maxX - 8 { reachedEdge = true }
            if pet.currentBehavior == .jumpDown || pet.currentBehavior == .fall { leftTheLedge = true }
        }

        XCTAssertTrue(reachedEdge, "Для чистоты теста питомец должен был дойти до края")
        XCTAssertFalse(leftTheLedge, "Прыгать некуда — сваливаться он не должен")
        XCTAssertEqual(pet.position.y, 400, accuracy: 0.001, "Остался на окне")
    }

    // MARK: - Вход из ходьбы

    func testWalkingOffTheEdgeCanTurnIntoAJump() {
        // roll = 0.3 попадает в полосу спрыгивания (hang 0…0.2, jumpDown 0.2…0.45).
        let pet = makePet(at: CGPoint(x: JumpScene.window.maxX - 10, y: JumpScene.window.y),
                          random: .fixed([0.3]))
        pet.update(0)
        pet.force(.walk)
        pet.facing = 1

        var ticks = 0
        while pet.currentBehavior == .walk, ticks < 200 { pet.update(1.0 / 30); ticks += 1 }
        XCTAssertEqual(pet.currentBehavior, .jumpDown)
    }

    // MARK: - Усталость и настройки

    func testJumpingCountsAsActivity() {
        let pet = makePet(at: CGPoint(x: 300, y: 0))
        pet.update(0)
        pet.force(.hop)
        run(pet, whileIn: .hop)
        XCTAssertGreaterThan(pet.activeTime, 0, "Прыжок — это активность")
    }

    func testJumpParametersAreReadFromTheBundledConfig() {
        // Конкретные числа здесь не пинятся: это ручки настройки, их крутят.
        // Проверяем, что они дочитались из JSON и осмысленны.
        let tuning = BehaviorConfig.load().tuning
        XCTAssertGreaterThan(tuning.hopSpeed, 0)
        XCTAssertGreaterThan(tuning.jumpSpeed, 0)
        XCTAssertGreaterThan(tuning.jumpLift, 0)
        XCTAssertTrue((0...1).contains(tuning.edgeJumpDownChance))
        XCTAssertTrue((0...1).contains(tuning.edgeHangChance))
        XCTAssertLessThanOrEqual(tuning.edgeHangChance + tuning.edgeJumpDownChance, 1,
                                 "Сумма шансов у края не должна превышать единицу")
    }

    func testEnergeticConditionTracksTiredness() {
        let config = BehaviorConfig.load()
        let machine = StateMachine(config: config, states: Pet.makeStates(), random: .fixed([0.5]))
        let pet = makePet(at: CGPoint(x: 300, y: 0))

        XCTAssertTrue(machine.isSatisfied(.energetic, pet: pet), "Свежий питомец полон сил")

        pet.force(.walk)
        for _ in 0..<Int(30 * config.tuning.sleepAfterActivity * 0.6) { pet.update(1.0 / 30) }
        XCTAssertFalse(machine.isSatisfied(.energetic, pet: pet), "Набегавшись, прыгать он не рвётся")
    }
}
