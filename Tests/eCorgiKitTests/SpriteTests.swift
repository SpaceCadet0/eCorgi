import XCTest
@testable import eCorgiKit

final class SpriteAtlasTests: XCTestCase {

    func testFileNameParsing() {
        XCTAssertEqual(SpriteAtlas.parse(fileName: "walk_07")?.action, .walk)
        XCTAssertEqual(SpriteAtlas.parse(fileName: "walk_07")?.index, 7)
        // Действие из двух слов: номер — только то, что после последнего «_».
        XCTAssertEqual(SpriteAtlas.parse(fileName: "sit_down_02")?.action, .sitDown)
        XCTAssertEqual(SpriteAtlas.parse(fileName: "sit_down_02")?.index, 2)
        XCTAssertNil(SpriteAtlas.parse(fileName: "walk"), "Без номера кадра файл не наш")
        XCTAssertNil(SpriteAtlas.parse(fileName: "unknown_01"), "Неизвестное действие игнорируется")
    }

    func testFallbackChainStartsWithRequestedAction() {
        for action in SpriteAction.allCases {
            XCTAssertEqual(SpriteAtlas.fallbackChain(for: action).first, action)
        }
    }

    func testEveryActionResolvesToFramesEvenWithPartialPack() {
        // В проекте сейчас лежат только кадры ходьбы — остальные должны
        // подменяться, иначе движок падал бы на первом же новом состоянии.
        let atlas = SpriteAtlas()
        for action in SpriteAction.allCases {
            XCTAssertFalse(atlas.frames(for: action).isEmpty, "Нет кадров для \(action.rawValue)")
        }
        XCTAssertGreaterThan(atlas.maxFrameSize.width, 0)
    }
}

final class SpriteAnimatorTests: XCTestCase {

    func testLoopingAnimationWrapsAround() {
        let animator = SpriteAnimator(atlas: SpriteAtlas(), action: .walk)
        animator.play(.walk, fps: 10, loops: true)
        let count = animator.frameCount
        XCTAssertGreaterThan(count, 1, "Для теста нужен многокадровый набор")

        for _ in 0..<count { animator.update(0.1) }
        XCTAssertEqual(animator.frameIndex, 0, "После полного круга возвращаемся на первый кадр")
        XCTAssertFalse(animator.isFinished)
    }

    func testNonLoopingAnimationStopsOnLastFrame() {
        let animator = SpriteAnimator(atlas: SpriteAtlas(), action: .idle)
        animator.play(.walk, fps: 10, loops: false)
        let count = animator.frameCount

        for _ in 0..<(count * 2) { animator.update(0.1) }
        XCTAssertEqual(animator.frameIndex, count - 1)
        XCTAssertTrue(animator.isFinished)
    }

    func testRepeatedPlayDoesNotResetProgress() {
        let animator = SpriteAnimator(atlas: SpriteAtlas(), action: .walk)
        animator.update(0.1)
        let index = animator.frameIndex
        animator.play(.walk, fps: 10)
        XCTAssertEqual(animator.frameIndex, index, "play() тем же действием не должен дёргать анимацию")
    }
}
