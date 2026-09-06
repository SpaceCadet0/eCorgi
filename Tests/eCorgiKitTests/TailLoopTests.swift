import AppKit
import XCTest
@testable import eCorgiKit

/// Хвостовая петля: анимация один раз проходит целиком, а дальше по кругу
/// идут только последние кадры.
final class TailLoopTests: XCTestCase {

    /// Атлас из заданного числа одноцветных кадров — нужен предсказуемый
    /// счётчик, а не настоящий пак, который меняется на ходу.
    private func atlas(frames count: Int, action: SpriteAction) -> SpriteAtlas {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tail-\(action.rawValue)-\(count)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<count {
            let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: Double(i) / Double(count), green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
            let data = rep.representation(using: .png, properties: [:])!
            try? data.write(to: dir.appendingPathComponent(String(format: "%@_%02d.png", action.rawValue, i)))
        }
        return SpriteAtlas(directory: dir)
    }

    /// Последовательность кадров за `steps` тиков.
    private func sequence(_ animator: SpriteAnimator, steps: Int, fps: Double = 10) -> [Int] {
        var seen = [animator.frameIndex]
        for _ in 0..<steps {
            animator.update(1.0 / fps)
            seen.append(animator.frameIndex)
        }
        return seen
    }

    func testFirstPassPlaysEveryFrameThenTailAlternates() {
        let animator = SpriteAnimator(atlas: atlas(frames: 6, action: .drag), action: .idle)
        animator.play(.drag, fps: 10, tail: 2)

        let seen = sequence(animator, steps: 9)
        XCTAssertEqual(Array(seen.prefix(6)), [0, 1, 2, 3, 4, 5], "Первый проход — все кадры подряд")
        XCTAssertEqual(Array(seen.dropFirst(6)), [4, 5, 4, 5], "Дальше чередуются два последних")
    }

    func testTailNeverEnds() {
        let animator = SpriteAnimator(atlas: atlas(frames: 5, action: .drag), action: .idle)
        animator.play(.drag, fps: 10, tail: 2)

        let seen = sequence(animator, steps: 60)
        XCTAssertFalse(animator.isFinished, "Хвостовая петля не заканчивается")
        XCTAssertTrue(Set(seen.dropFirst(5)).isSubset(of: [3, 4]),
                      "После первого прохода показываются только два последних кадра")
    }

    func testTailStartIsReported() {
        let animator = SpriteAnimator(atlas: atlas(frames: 7, action: .drag), action: .idle)
        animator.play(.drag, fps: 10, tail: 3)
        XCTAssertEqual(animator.tailStart, 4, "Хвост из трёх кадров начинается с пятого")
    }

    func testTailLongerThanAnimationBehavesAsAPlainLoop() {
        let animator = SpriteAnimator(atlas: atlas(frames: 3, action: .drag), action: .idle)
        animator.play(.drag, fps: 10, tail: 10)

        let seen = sequence(animator, steps: 6)
        XCTAssertEqual(seen, [0, 1, 2, 0, 1, 2, 0])
    }

    func testWithoutTailAnimationLoopsFromTheStart() {
        let animator = SpriteAnimator(atlas: atlas(frames: 4, action: .drag), action: .idle)
        animator.play(.drag, fps: 10)

        XCTAssertEqual(sequence(animator, steps: 5), [0, 1, 2, 3, 0, 1])
    }

    func testDragDeclaresATwoFrameTail() {
        XCTAssertEqual(Pet.animations[.drag]?.tail, 2, "Перетаскивание крутит два последних кадра")
        for id in BehaviorID.allCases where id != .drag {
            XCTAssertEqual(Pet.animations[id]?.tail, 0, "У \(id.rawValue) хвост не задан")
        }
    }

    func testDraggedPetEndsUpInTheTail() {
        let ground = Ledge(y: 0, minX: 0, maxX: 1200, kind: .ground)
        let pet = Pet(atlas: SpriteAtlas(),
                      environment: ScreenEnvironment(fixedLedges: [ground],
                                                     worldBounds: CGRect(x: 0, y: 0, width: 1200, height: 900)),
                      settings: .testStore(), random: .fixed([0.5]),
                      position: CGPoint(x: 400, y: 0))
        pet.isDragged = true
        pet.dragTarget = CGPoint(x: 400, y: 200)
        for _ in 0..<120 { pet.update(1.0 / 30) }

        XCTAssertEqual(pet.currentBehavior, .drag)
        XCTAssertGreaterThanOrEqual(pet.animator.frameIndex, pet.animator.tailStart,
                                    "Через две секунды перетаскивания анимация должна крутиться на хвосте")
    }
}
