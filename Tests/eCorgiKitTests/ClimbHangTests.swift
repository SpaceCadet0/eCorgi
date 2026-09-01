import XCTest
@testable import eCorgiKit

/// Мир из одного окна: пол, верхняя грань окна и её левая стена.
private struct Scene {
    static let groundY: CGFloat = 0
    static let windowMinX: CGFloat = 500
    static let windowMaxX: CGFloat = 800
    static let windowBottomY: CGFloat = 40
    static let windowTopY: CGFloat = 400

    static let ground = Ledge(y: groundY, minX: 0, maxX: 1200, kind: .ground)
    static let windowTop = Ledge(y: windowTopY, minX: windowMinX, maxX: windowMaxX, kind: .windowTop)
    static let leftWall = Wall(x: windowMinX, minY: windowBottomY, maxY: windowTopY, side: .left)
}

final class ClimbHangTests: XCTestCase {

    private func makePet(ledges: [Ledge] = [Scene.ground, Scene.windowTop],
                         walls: [Wall] = [Scene.leftWall],
                         at position: CGPoint,
                         random: RandomSource = .fixed([0.5])) -> Pet {
        let environment = ScreenEnvironment(fixedLedges: ledges,
                                            fixedWalls: walls,
                                            worldBounds: CGRect(x: 0, y: 0, width: 1200, height: 900))
        return Pet(atlas: SpriteAtlas(),
                   environment: environment,
                   settings: .testStore(),
                   random: random,
                   position: position)
    }

    /// Крутит тик, пока питомец не выйдет из заданного состояния.
    @discardableResult
    private func run(_ pet: Pet, whileIn behavior: BehaviorID, maxTicks: Int = 600) -> Int {
        var ticks = 0
        while pet.currentBehavior == behavior, ticks < maxTicks {
            pet.update(1.0 / 30)
            ticks += 1
        }
        return ticks
    }

    // MARK: - Поиск граней

    func testWallInFrontIsClimbable() {
        let pet = makePet(at: CGPoint(x: Scene.windowMinX - 5, y: Scene.groundY))
        pet.update(0)
        XCTAssertEqual(pet.climbableWall(direction: 1), Scene.leftWall)
    }

    func testWallBehindIsIgnoredWhenDirectionGiven() {
        let pet = makePet(at: CGPoint(x: Scene.windowMinX - 5, y: Scene.groundY))
        pet.update(0)
        // Стена справа, а питомец идёт влево — цепляться не за что.
        XCTAssertNil(pet.climbableWall(direction: -1))
    }

    func testTooShortWallIsNotWorthClimbing() {
        let stub = Wall(x: Scene.windowMinX, minY: 0, maxY: 30, side: .left)
        let pet = makePet(walls: [stub], at: CGPoint(x: Scene.windowMinX - 5, y: Scene.groundY))
        pet.update(0)
        XCTAssertNil(pet.climbableWall(), "Подъём ниже minClimbHeight не считается")
    }

    func testWallStartingTooHighIsOutOfReach() {
        let floating = Wall(x: Scene.windowMinX, minY: 400, maxY: 800, side: .left)
        let pet = makePet(walls: [floating], at: CGPoint(x: Scene.windowMinX - 5, y: Scene.groundY))
        pet.update(0)
        XCTAssertNil(pet.climbableWall(), "До грани, начинающейся высоко над головой, не дотянуться")
    }

    func testHangAnchorOnlyNearTheEndsOfAWindowLedge() {
        let left = makePet(at: CGPoint(x: Scene.windowMinX + 10, y: Scene.windowTopY))
        left.update(0)
        XCTAssertEqual(left.hangAnchorAtEdge()?.side, .left)
        XCTAssertEqual(left.hangAnchorAtEdge()?.x, Scene.windowMinX)

        let right = makePet(at: CGPoint(x: Scene.windowMaxX - 10, y: Scene.windowTopY))
        right.update(0)
        XCTAssertEqual(right.hangAnchorAtEdge()?.side, .right)

        let middle = makePet(at: CGPoint(x: 650, y: Scene.windowTopY))
        middle.update(0)
        XCTAssertNil(middle.hangAnchorAtEdge(), "Посреди окна свешиваться не с чего")
    }

    func testHangAnchorIsNotOfferedOnTheGround() {
        let pet = makePet(at: CGPoint(x: 300, y: Scene.groundY))
        pet.update(0)
        XCTAssertNil(pet.hangAnchorAtEdge(), "С нижнего края экрана не свесишься")
    }

    // MARK: - Не засиживаться наверху

    func testTimeOnWindowResetsOnlyOnTheGround() {
        let onWindow = makePet(at: CGPoint(x: 650, y: Scene.windowTopY))
        for _ in 0..<60 { onWindow.update(1.0 / 30) }
        XCTAssertGreaterThan(onWindow.timeOnWindow, 1.5)

        let onGround = makePet(at: CGPoint(x: 300, y: Scene.groundY))
        for _ in 0..<60 { onGround.update(1.0 / 30) }
        XCTAssertEqual(onGround.timeOnWindow, 0, accuracy: 0.001)
    }

    func testOverstayingPetWalksToTheEdgeAndJumpsDown() {
        // Ставим посреди широкого заголовка: случайным блужданием до края
        // он бы почти никогда не дошёл.
        let pet = makePet(at: CGPoint(x: 650, y: Scene.windowTopY))
        pet.update(0)

        var ticks = 0
        let limit = Int(30 * (pet.tuning.windowStayLimit + 40))
        while pet.position.y > Scene.groundY, ticks < limit {
            pet.update(1.0 / 30)
            ticks += 1
        }

        XCTAssertEqual(pet.position.y, Scene.groundY, accuracy: 0.001,
                       "Засидевшись наверху, питомец должен спуститься сам")
        XCTAssertLessThan(Double(ticks) / 30, pet.tuning.windowStayLimit + 40)
    }

    func testPetDoesNotRushDownBeforeTheLimit() {
        let pet = makePet(at: CGPoint(x: 650, y: Scene.windowTopY))
        for _ in 0..<Int(30 * 5) { pet.update(1.0 / 30) }
        XCTAssertFalse(pet.hasOverstayedOnWindow, "Пять секунд — ещё не засиделся")
    }

    // MARK: - Положение тела у грани

    func testBodyHangsOutsideTheWindowWhenThereIsRoom() {
        let pet = makePet(at: CGPoint(x: Scene.windowMinX, y: Scene.groundY))
        let x = pet.bodyX(besideEdgeAt: Scene.windowMinX, side: .left)
        XCTAssertLessThan(x, Scene.windowMinX, "У левой грани тело оказывается слева от окна")
        XCTAssertEqual(x, Scene.windowMinX - pet.wallHugOffset, accuracy: 0.001)
    }

    func testBodyStaysOnScreenAtTheDisplayEdge() {
        // Окно во весь экран: «снаружи» его левой грани — уже за пределами экрана.
        let pet = makePet(at: CGPoint(x: 0, y: Scene.groundY))
        let x = pet.bodyX(besideEdgeAt: 0, side: .left)
        XCTAssertGreaterThan(x, 0, "У края экрана нужно лезть по внутренней стороне")

        let right = pet.bodyX(besideEdgeAt: 1200, side: .right)
        XCTAssertLessThan(right, 1200)
    }

    // MARK: - Поиск цели для прогулки

    func testWalkHeadsTowardsAWallWhenItDecidesTo() {
        // unit() = 0.1 < seekWallChance (0.4) — прогулка получает цель.
        let pet = makePet(at: CGPoint(x: 200, y: Scene.groundY), random: .fixed([0.1]))
        pet.update(0)
        pet.force(.walk)
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.facing, 1, "Грань справа — значит идём вправо")
        XCTAssertGreaterThan(pet.position.x, 200)
    }

    func testDistantWallIsVisibleOnlyToTheSeekingSearch() {
        let pet = makePet(at: CGPoint(x: 200, y: Scene.groundY))
        pet.update(0)
        XCTAssertNil(pet.climbableWall(), "За 300 пунктов рукой не достать")
        XCTAssertEqual(pet.climbableWall(maxDistance: 1000), Scene.leftWall)
    }

    // MARK: - Climb

    func testClimbCarriesPetOntoTheWindowTop() {
        let pet = makePet(at: CGPoint(x: Scene.windowMinX - 5, y: Scene.groundY))
        pet.update(0)
        pet.climbTarget = Scene.leftWall
        pet.force(.climb)

        run(pet, whileIn: .climb)

        XCTAssertEqual(pet.currentBehavior, .land)
        XCTAssertEqual(pet.position.y, Scene.windowTopY, accuracy: 0.001)
        XCTAssertGreaterThan(pet.position.x, Scene.windowMinX, "Наверху нужно переступить внутрь полки")

        pet.update(1.0 / 30)   // опора пересчитывается в начале тика
        XCTAssertEqual(pet.support?.kind, .windowTop)
    }

    func testClimbFacesTheWindow() {
        let pet = makePet(at: CGPoint(x: Scene.windowMinX - 5, y: Scene.groundY))
        pet.climbTarget = Scene.leftWall
        pet.force(.climb)
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.facing, 1, "На левой грани питомец смотрит вправо, на окно")
    }

    func testClimbFallsWhenTheWindowDisappears() {
        // Стена есть, а верхней грани нет — её перекрыло чужое окно.
        let pet = makePet(ledges: [Scene.ground], at: CGPoint(x: Scene.windowMinX - 5, y: Scene.groundY))
        pet.update(0)
        pet.climbTarget = Scene.leftWall
        pet.force(.climb)

        run(pet, whileIn: .climb)
        XCTAssertEqual(pet.currentBehavior, .fall, "Наверху не за что зацепиться — падаем")
    }

    func testClimbWithoutAnyWallGivesUpInsteadOfFalling() {
        let pet = makePet(walls: [], at: CGPoint(x: 300, y: Scene.groundY))
        pet.update(0)
        pet.force(.climb)
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.currentBehavior, .idle, "Стены нет, но под лапами пол — падать незачем")
    }

    // MARK: - Hang

    func testHangPositionsBodyBelowTheGrabPoint() {
        let pet = makePet(at: CGPoint(x: Scene.windowMinX + 5, y: Scene.windowTopY))
        pet.update(0)
        pet.hangAnchor = HangAnchor(x: Scene.windowMinX, y: Scene.windowTopY, side: .left)
        pet.force(.hang)
        pet.update(1.0 / 30)

        XCTAssertEqual(pet.position.y, Scene.windowTopY - pet.spriteHeight, accuracy: 0.001)
        XCTAssertLessThan(pet.position.x, Scene.windowMinX, "Тело висит снаружи окна")
        XCTAssertEqual(pet.facing, 1)
    }

    func testHangSwaysAndSettlesDown() {
        let pet = makePet(at: CGPoint(x: Scene.windowMinX + 5, y: Scene.windowTopY))
        pet.update(0)
        pet.hangAnchor = HangAnchor(x: Scene.windowMinX, y: Scene.windowTopY, side: .left)
        pet.force(.hang)

        var peak: CGFloat = 0
        for _ in 0..<15 {
            pet.update(1.0 / 30)
            peak = max(peak, abs(pet.sway))
        }
        XCTAssertGreaterThan(peak, 0.01, "Сразу после захвата питомец должен раскачиваться")
        XCTAssertLessThanOrEqual(peak, pet.tuning.hangSwayAmplitude + 0.001)
    }

    func testHangPullsBackUpOntoTheLedge() {
        // unit() = 0.1 < hangPullUpChance (0.6) — подтягивается.
        let pet = makePet(at: CGPoint(x: Scene.windowMinX + 5, y: Scene.windowTopY),
                          random: .fixed([0.1]))
        pet.update(0)
        pet.hangAnchor = HangAnchor(x: Scene.windowMinX, y: Scene.windowTopY, side: .left)
        pet.force(.hang)

        run(pet, whileIn: .hang)

        XCTAssertEqual(pet.position.y, Scene.windowTopY, accuracy: 0.001)
        XCTAssertEqual(pet.sway, 0, "После подвеса наклон надо сбросить")

        pet.update(1.0 / 30)
        XCTAssertEqual(pet.support?.kind, .windowTop)
    }

    func testPullUpStepsClearOfTheGrabZone() {
        let pet = makePet(at: CGPoint(x: Scene.windowMinX + 5, y: Scene.windowTopY),
                          random: .fixed([0.1]))
        pet.update(0)
        pet.hangAnchor = HangAnchor(x: Scene.windowMinX, y: Scene.windowTopY, side: .left)
        pet.force(.hang)

        run(pet, whileIn: .hang)
        pet.update(1.0 / 30)

        XCTAssertNil(pet.hangAnchorAtEdge(),
                     "Подтянувшись, питомец не должен сразу снова оказаться у края")
    }

    func testHangLetsGoAndFalls() {
        // unit() = 0.9 > hangPullUpChance (0.6) — разжимает лапы.
        let pet = makePet(at: CGPoint(x: Scene.windowMinX + 5, y: Scene.windowTopY),
                          random: .fixed([0.9]))
        pet.update(0)
        pet.hangAnchor = HangAnchor(x: Scene.windowMinX, y: Scene.windowTopY, side: .left)
        pet.force(.hang)

        run(pet, whileIn: .hang)
        XCTAssertEqual(pet.currentBehavior, .fall)

        // И в итоге приземляется на пол под окном.
        for _ in 0..<200 { pet.update(1.0 / 30) }
        XCTAssertEqual(pet.position.y, Scene.groundY, accuracy: 0.001)
    }

    func testHangFallsWhenTheLedgeVanishes() {
        let pet = makePet(at: CGPoint(x: Scene.windowMinX + 5, y: Scene.windowTopY))
        pet.update(0)
        pet.hangAnchor = HangAnchor(x: 999, y: 999, side: .left)   // грани с такой геометрией нет
        pet.force(.hang)
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.currentBehavior, .fall)
    }

    func testHangIsNotInterruptedByTheDirectorDespiteHavingNoSupport() {
        let pet = makePet(at: CGPoint(x: Scene.windowMinX + 5, y: Scene.windowTopY))
        pet.update(0)
        pet.hangAnchor = HangAnchor(x: Scene.windowMinX, y: Scene.windowTopY, side: .left)
        pet.force(.hang)

        for _ in 0..<20 { pet.update(1.0 / 30) }
        XCTAssertNil(pet.support, "Вися на грани, опоры под лапами нет")
        XCTAssertEqual(pet.currentBehavior, .hang, "…но это не повод включать падение")
    }
}
