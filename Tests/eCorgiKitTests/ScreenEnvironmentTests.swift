import XCTest
@testable import eCorgiKit

final class ScreenEnvironmentTests: XCTestCase {

    func testCoordinateFlipFromCoreGraphicsToAppKit() {
        // Окно 800×600, верхний край в 100 пунктах от верха экрана высотой 1000.
        let cg = CGRect(x: 50, y: 100, width: 800, height: 600)
        let appKit = ScreenEnvironment.convertToAppKit(cg, primaryMaxY: 1000)
        XCTAssertEqual(appKit.minX, 50)
        XCTAssertEqual(appKit.maxY, 900, "Верх окна в AppKit — это 1000 − 100")
        XCTAssertEqual(appKit.height, 600)
    }

    func testFixedEnvironmentDoesNotTouchSystem() {
        let ledge = Ledge(y: 0, minX: 0, maxX: 100, kind: .ground)
        let env = ScreenEnvironment(fixedLedges: [ledge], worldBounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        env.update(10, urgency: .high)
        XCTAssertEqual(env.ledges, [ledge])
    }
}
