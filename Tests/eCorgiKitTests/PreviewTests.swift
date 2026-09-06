import XCTest
@testable import eCorgiKit

/// Режим проверки анимаций из меню «Тест».
final class PreviewTests: XCTestCase {

    private func makePet() -> Pet {
        let ground = Ledge(y: 0, minX: 0, maxX: 1200, kind: .ground)
        return Pet(atlas: SpriteAtlas(),
                   environment: ScreenEnvironment(fixedLedges: [ground],
                                                  worldBounds: CGRect(x: 0, y: 0, width: 1200, height: 900)),
                   settings: .testStore(),
                   random: .fixed([0.5]),
                   position: CGPoint(x: 400, y: 0))
    }

    func testEveryBehaviourDeclaresItsAnimation() {
        // Таблица собирается из самих состояний, поэтому разойтись с экраном
        // не может — но пропустить новое поведение вполне.
        for id in BehaviorID.allCases {
            XCTAssertNotNil(Pet.animations[id], "У поведения \(id.rawValue) не объявлена анимация")
        }
    }

    func testTestMenuListsEveryBehaviour() {
        let listed = Set(StatusItemController.testable.map(\.0))
        for id in BehaviorID.allCases {
            XCTAssertTrue(listed.contains(id), "Поведение \(id.rawValue) не попало в меню «Тест»")
        }
        XCTAssertEqual(listed.count, StatusItemController.testable.count, "В меню есть повторы")
    }

    func testPreviewPlaysTheChosenAnimation() {
        let pet = makePet()
        pet.previewBehavior = .climb
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.animator.action, Pet.animations[.climb]?.action)
    }

    func testPreviewHoldsStatesThatWouldOtherwiseCancelThemselves() {
        // Лазание без подходящего окна обычно отменяет само себя; в режиме
        // проверки анимацию нужно всё-таки увидеть.
        let pet = makePet()
        pet.previewBehavior = .climb
        for _ in 0..<60 { pet.update(1.0 / 30) }
        XCTAssertEqual(pet.animator.action, .climb)
    }

    func testPreviewKeepsThePetInPlace() {
        let pet = makePet()
        pet.previewBehavior = .walk
        for _ in 0..<60 { pet.update(1.0 / 30) }
        XCTAssertEqual(pet.position.x, 400, accuracy: 0.001, "В режиме проверки питомец не разгуливает")
    }

    func testPreviewStillAllowsDragging() {
        let pet = makePet()
        pet.previewBehavior = .sleep
        pet.isDragged = true
        pet.dragTarget = CGPoint(x: 700, y: 300)
        pet.update(1.0 / 30)
        XCTAssertEqual(pet.position, CGPoint(x: 700, y: 300))
    }

    func testLeavingPreviewReturnsThePetToLife() {
        let pet = makePet()
        pet.previewBehavior = .fall
        pet.update(1.0 / 30)
        pet.previewBehavior = nil
        for _ in 0..<30 { pet.update(1.0 / 30) }
        XCTAssertNotEqual(pet.currentBehavior, .fall, "На полу питомец падать не должен")
    }

    func testAtlasReportsWhichActionActuallySuppliesFrames() {
        let atlas = SpriteAtlas()
        for action in SpriteAction.allCases {
            let source = atlas.source(for: action)
            XCTAssertGreaterThan(source.frames, 0)
            if atlas.hasOwnFrames(for: action) {
                XCTAssertEqual(source.action, action, "Свои кадры подменять нечем")
            } else {
                XCTAssertNotEqual(source.action, action, "\(action.rawValue) без своих кадров — должна быть подмена")
            }
        }
    }
}
