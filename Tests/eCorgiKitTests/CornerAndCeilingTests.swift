import AppKit
import XCTest
@testable import eCorgiKit

/// Два дефекта, которые видно только на живом экране: невидимый потолок,
/// поставленный AppKit, и застревание в углу.
final class CornerAndCeilingTests: XCTestCase {

    private static let ground = Ledge(y: 0, minX: 0, maxX: 1200, kind: .ground)

    private func makePet(at position: CGPoint, facing: CGFloat) -> Pet {
        let environment = ScreenEnvironment(fixedLedges: [Self.ground],
                                            worldBounds: CGRect(x: 0, y: 0, width: 1200, height: 900))
        let pet = Pet(atlas: SpriteAtlas(),
                      environment: environment,
                      settings: .testStore(),
                      random: .fixed([0.5]),
                      position: position)
        pet.update(0)
        pet.force(.walk)
        pet.facing = facing
        return pet
    }

    /// Сколько раз питомец сменил направление за прогон.
    private func walk(_ pet: Pet, ticks: Int) -> (flips: Int, travelled: CGFloat) {
        let startX = pet.position.x
        var flips = 0
        var facing = pet.facing
        for _ in 0..<ticks {
            pet.update(1.0 / 30)
            if pet.facing != facing { flips += 1; facing = pet.facing }
        }
        return (flips, abs(pet.position.x - startX))
    }

    // MARK: - Угол экрана

    func testPetEscapesTheLeftCorner() {
        // Оказавшись вплотную к краю (после падения, броска или клампа),
        // питомец разворачивался туда-обратно на каждом тике и не сходил с места.
        let pet = makePet(at: CGPoint(x: Self.ground.minX + 2, y: 0), facing: -1)
        let result = walk(pet, ticks: 60)

        XCTAssertGreaterThan(result.travelled, 20, "Из угла нужно выбираться, а не топтаться в нём")
        XCTAssertLessThanOrEqual(result.flips, 2, "И не мигать направлением каждый кадр")
    }

    func testPetEscapesTheRightCorner() {
        let pet = makePet(at: CGPoint(x: Self.ground.maxX - 2, y: 0), facing: 1)
        let result = walk(pet, ticks: 60)

        XCTAssertGreaterThan(result.travelled, 20)
        XCTAssertLessThanOrEqual(result.flips, 2)
    }

    func testPetExactlyOnTheCornerStillWalksAway() {
        let pet = makePet(at: CGPoint(x: Self.ground.minX, y: 0), facing: -1)
        let result = walk(pet, ticks: 90)
        XCTAssertGreaterThan(result.travelled, 20)
    }

    func testWalkingAwayFromAnEdgeIsNotTreatedAsReachingIt() {
        // Питомец у левого края, но идёт вправо — края он не достиг.
        let pet = makePet(at: CGPoint(x: Self.ground.minX + 3, y: 0), facing: 1)
        let result = walk(pet, ticks: 30)
        XCTAssertEqual(result.flips, 0, "Разворачиваться не с чего")
        XCTAssertGreaterThan(pet.position.x, Self.ground.minX + 3)
    }

    // MARK: - Потолок от AppKit

    func testPetPanelIsNotPulledDownByTheSystem() {
        // AppKit по умолчанию не даёт окну уйти выше видимой области: он
        // подтягивает его вниз, и питомец упирается в невидимый потолок.
        let panel = PetPanel(contentRect: CGRect(x: 0, y: 0, width: 100, height: 98),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered,
                             defer: true)
        let wanted = CGRect(x: 400, y: 942, width: 100, height: 98)
        XCTAssertEqual(panel.constrainFrameRect(wanted, to: NSScreen.main), wanted,
                       "Окно питомца должно вставать ровно туда, куда его просят")
    }
}
