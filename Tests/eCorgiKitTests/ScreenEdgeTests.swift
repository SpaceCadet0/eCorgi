import AppKit
import XCTest
@testable import eCorgiKit

/// Питомец не должен выезжать за край экрана.
///
/// Точка положения лежит в середине холста, поэтому ограничение по ней
/// оставляло половину спрайта за экраном. Ограничивать надо по нарисованному
/// персонажу — и холст тут тоже не мера: он шире рисунка.
final class ScreenEdgeTests: XCTestCase {

    private static let world = CGRect(x: 0, y: 0, width: 1200, height: 900)
    private static let ground = Ledge(y: 0, minX: 0, maxX: 1200, kind: .ground)

    private func makePet(at x: CGFloat, facing: CGFloat = 1) -> Pet {
        let environment = ScreenEnvironment(fixedLedges: [Self.ground], worldBounds: Self.world)
        let pet = Pet(atlas: SpriteAtlas(),
                      environment: environment,
                      settings: .testStore(),
                      random: .fixed([0.5]),
                      position: CGPoint(x: x, y: 0))
        pet.update(0)
        pet.facing = facing
        return pet
    }

    /// Левый и правый край нарисованного персонажа на экране.
    private func edges(_ pet: Pet) -> (left: CGFloat, right: CGFloat) {
        let span = pet.contentSpan
        return (pet.position.x + span.left, pet.position.x + span.right)
    }

    // MARK: - Мера выступа

    func testSpanIsMeasuredFromTheDrawingNotTheCanvas() {
        let pet = makePet(at: 600)
        let span = pet.contentSpan
        let canvasHalf = pet.animator.currentFrame.size.width / 2

        XCTAssertLessThan(span.left, 0, "Влево персонаж выступает")
        XCTAssertGreaterThan(span.right, 0, "И вправо тоже")
        // У кадра, обрезанного вплотную по рисунку, выступ равен половине
        // холста; у кадра с полями — меньше. Больше быть не может никогда.
        XCTAssertGreaterThanOrEqual(span.left, -canvasHalf)
        XCTAssertLessThanOrEqual(span.right, canvasHalf)
    }

    // MARK: - Ограничение положения

    func testPetPushedPastTheLeftEdgeStaysOnScreen() {
        let pet = makePet(at: 600)
        pet.position.x = -500          // как после броска мышью
        pet.update(1.0 / 30)
        XCTAssertGreaterThanOrEqual(edges(pet).left, Self.world.minX - 0.5)
    }

    func testPetPushedPastTheRightEdgeStaysOnScreen() {
        let pet = makePet(at: 600)
        pet.position.x = 5000
        pet.update(1.0 / 30)
        XCTAssertLessThanOrEqual(edges(pet).right, Self.world.maxX + 0.5)
    }

    func testDraggedPetCannotBeCarriedOffScreen() {
        let pet = makePet(at: 600)
        pet.isDragged = true
        pet.dragTarget = CGPoint(x: -800, y: 200)
        for _ in 0..<90 { pet.update(1.0 / 30) }
        XCTAssertGreaterThanOrEqual(edges(pet).left, Self.world.minX - 0.5)
    }

    // MARK: - Ходьба

    func testWalkingLeftTurnsAroundBeforeLeavingTheScreen() {
        let pet = makePet(at: 60, facing: -1)
        pet.force(.walk)
        pet.facing = -1

        var minLeft = CGFloat.greatestFiniteMagnitude
        for _ in 0..<180 {
            pet.update(1.0 / 30)
            minLeft = min(minLeft, edges(pet).left)
        }
        XCTAssertGreaterThanOrEqual(minLeft, Self.world.minX - 0.5,
                                    "Персонаж не должен зайти за левый край")
    }

    func testWalkingRightTurnsAroundBeforeLeavingTheScreen() {
        let pet = makePet(at: Self.world.maxX - 60, facing: 1)
        pet.force(.walk)
        pet.facing = 1

        var maxRight: CGFloat = 0
        for _ in 0..<180 {
            pet.update(1.0 / 30)
            maxRight = max(maxRight, edges(pet).right)
        }
        XCTAssertLessThanOrEqual(maxRight, Self.world.maxX + 0.5)
    }

    func testPetAtTheEdgeKeepsWalkingInsteadOfSlidingInPlace() {
        // Питомец у самого края: он должен развернуться и уйти, а не
        // перебирать лапами, упираясь в ограничитель.
        let pet = makePet(at: 0, facing: -1)
        pet.force(.walk)
        pet.facing = -1
        let startX = pet.position.x

        for _ in 0..<60 { pet.update(1.0 / 30) }
        XCTAssertGreaterThan(pet.position.x - startX, 20)
    }

    // MARK: - Полки внутри экрана

    func testLedgeAwayFromTheEdgesIsNotNarrowed() {
        let window = Ledge(y: 400, minX: 400, maxX: 800, kind: .windowTop)
        let environment = ScreenEnvironment(fixedLedges: [Self.ground, window], worldBounds: Self.world)
        let pet = Pet(atlas: SpriteAtlas(), environment: environment, settings: .testStore(),
                      random: .fixed([0.5]), position: CGPoint(x: 600, y: 400))
        pet.update(0)

        let span = pet.walkableSpan(of: window)
        XCTAssertEqual(span.minX, window.minX, "Полка вдали от краёв экрана сужаться не должна")
        XCTAssertEqual(span.maxX, window.maxX)
    }

    func testGroundSpanIsNarrowedByTheOverhang() {
        let pet = makePet(at: 600)
        let span = pet.walkableSpan(of: Self.ground)
        XCTAssertGreaterThan(span.minX, Self.ground.minX, "Пол упирается в края экрана — отрезок уже")
        XCTAssertLessThan(span.maxX, Self.ground.maxX)
    }
}
