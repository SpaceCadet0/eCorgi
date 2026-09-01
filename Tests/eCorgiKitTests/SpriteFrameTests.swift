import AppKit
import XCTest
@testable import eCorgiKit

/// Замеры по содержимому кадра. После приведения пака к общему холсту над
/// мелкими рисунками остаётся пустота, и всё, что движок берёт «по кадру»,
/// обязано считаться по непрозрачным пикселям, а не по холсту.
final class SpriteFrameTests: XCTestCase {

    /// Кадр 100x200, где закрашена только нижняя четверть — как маленький
    /// персонаж на большом общем холсте.
    private func frameWithContentAtBottom() -> SpriteFrame {
        let width = 100, height = 200
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(NSColor.orange.cgColor)
        // Начало координат CGContext внизу слева.
        ctx.fill(CGRect(x: 20, y: 0, width: 60, height: 50))
        return SpriteFrame(image: ctx.makeImage()!, size: CGSize(width: width, height: height))
    }

    func testContentBoundsMeasureTheDrawingNotTheCanvas() {
        let bounds = frameWithContentAtBottom().contentBounds
        XCTAssertEqual(bounds.minY, 0, accuracy: 3, "Персонаж стоит на нижней кромке холста")
        XCTAssertEqual(bounds.height, 50, accuracy: 5)
        XCTAssertEqual(bounds.width, 60, accuracy: 5)
        XCTAssertEqual(bounds.midX, 50, accuracy: 3)
    }

    func testContentTopIsFarBelowTheCanvasTop() {
        // Именно по этой величине питомец подвешивается к грани окна: по холсту
        // он висел бы на 200 пунктов ниже, чем нужно.
        let bounds = frameWithContentAtBottom().contentBounds
        XCTAssertLessThan(bounds.maxY, 60)
    }

    func testOpacityProbeIsNotVerticallyFlipped() {
        // Маска строится в буфере CGContext, где строка 0 — верх кадра,
        // а координата приходит снизу. Без переворота выходило зеркало:
        // кликалась пустота над персонажем, а сам он мышью не брался.
        let frame = frameWithContentAtBottom()
        XCTAssertTrue(frame.isOpaque(atUnit: CGPoint(x: 0.5, y: 0.1)), "Низ кадра закрашен")
        XCTAssertFalse(frame.isOpaque(atUnit: CGPoint(x: 0.5, y: 0.9)), "Верх кадра пуст")
    }

    func testOpacityProbeRespectsHorizontalBounds() {
        let frame = frameWithContentAtBottom()
        XCTAssertTrue(frame.isOpaque(atUnit: CGPoint(x: 0.5, y: 0.1)))
        XCTAssertFalse(frame.isOpaque(atUnit: CGPoint(x: 0.05, y: 0.1)), "Слева от рисунка пусто")
        XCTAssertFalse(frame.isOpaque(atUnit: CGPoint(x: 0.95, y: 0.1)), "Справа тоже")
    }

    func testBundledPackSharesOneCanvasSize() {
        let atlas = SpriteAtlas()
        var canvases = Set<String>()
        for action in SpriteAction.allCases {
            for frame in atlas.frames(for: action) {
                canvases.insert("\(Int(frame.size.width))x\(Int(frame.size.height))")
            }
        }
        XCTAssertEqual(canvases.count, 1, "Кадры пака должны лежать на одном холсте: \(canvases.sorted())")
    }
}
