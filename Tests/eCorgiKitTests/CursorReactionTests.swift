import XCTest
@testable import eCorgiKit

/// Реакция на курсор. Положение мыши подставляется, иначе тест зависел бы
/// от того, где сейчас настоящий курсор на машине.
final class CursorReactionTests: XCTestCase {

    private static let ground = Ledge(y: 0, minX: 0, maxX: 1200, kind: .ground)
    private static let petSpot = CGPoint(x: 400, y: 0)

    /// Курсор вплотную к питомцу.
    private static let nearby = CGPoint(x: 410, y: 30)
    /// Курсор на другом конце экрана.
    private static let faraway = CGPoint(x: 1100, y: 600)

    private func makePet(cursorAt point: CGPoint) -> Pet {
        let environment = ScreenEnvironment(fixedLedges: [Self.ground],
                                            worldBounds: CGRect(x: 0, y: 0, width: 1200, height: 900))
        let settings = SettingsStore.testStore()
        settings.reactToCursor = true
        return Pet(atlas: SpriteAtlas(),
                   environment: environment,
                   cursor: CursorTracker(source: { point }),
                   settings: settings,
                   random: .fixed([0.5]),
                   position: Self.petSpot)
    }

    private func tick(_ pet: Pet, seconds: Double = 0.5) {
        for _ in 0..<Int(seconds * 30) { pet.update(1.0 / 30) }
    }

    // MARK: - Обычные состояния питомца спугнуть можно

    func testIdlePetRunsFromANearbyCursor() {
        let pet = makePet(cursorAt: Self.nearby)
        pet.force(.idle)
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.currentBehavior, .runFromCursor)
    }

    func testWalkingPetRunsFromANearbyCursor() {
        let pet = makePet(cursorAt: Self.nearby)
        pet.force(.walk)
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.currentBehavior, .runFromCursor)
    }

    func testDistantCursorLeavesThePetAlone() {
        let pet = makePet(cursorAt: Self.faraway)
        pet.force(.idle)
        tick(pet)
        XCTAssertNotEqual(pet.currentBehavior, .runFromCursor)
    }

    // MARK: - Сон и дрёму курсор не трогает

    func testSleepingPetIgnoresTheCursor() {
        let pet = makePet(cursorAt: Self.nearby)
        pet.force(.sleep)
        tick(pet, seconds: 3)
        XCTAssertEqual(pet.currentBehavior, .sleep, "Спящего мышь поднимать не должна")
    }

    func testSettlingPetIgnoresTheCursor() {
        let pet = makePet(cursorAt: Self.nearby)
        pet.force(.settleDown)
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.currentBehavior, .settleDown, "Укладывающегося — тоже")
    }

    func testWakingPetCanStillBeStartled() {
        // Пробуждение — уже не сон: питомец поднимается, и спугнуть его можно.
        let pet = makePet(cursorAt: Self.nearby)
        pet.force(.wakeUp)
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.currentBehavior, .runFromCursor)
    }

    func testSleepingPetCanStillBePickedUp() {
        // Единственный способ поднять спящего мышью — взять его в руки.
        let pet = makePet(cursorAt: Self.nearby)
        pet.force(.sleep)
        tick(pet)
        XCTAssertEqual(pet.currentBehavior, .sleep)

        pet.isDragged = true
        pet.dragTarget = CGPoint(x: 500, y: 300)
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.currentBehavior, .drag)
    }

    func testSleepingPetCanStillBeWokenFromTheMenu() {
        let pet = makePet(cursorAt: Self.nearby)
        pet.force(.sleep)
        tick(pet)

        pet.force(.wakeUp)   // то же самое делает пункт меню «Разбудить»
        XCTAssertEqual(pet.currentBehavior, .wakeUp)
    }

    // MARK: - Настройка

    func testCursorReactionCanBeSwitchedOffEntirely() {
        let pet = makePet(cursorAt: Self.nearby)
        pet.settings.reactToCursor = false
        pet.force(.idle)
        tick(pet)
        XCTAssertNotEqual(pet.currentBehavior, .runFromCursor)
        pet.settings.reactToCursor = true
    }
}
