import XCTest
@testable import eCorgiKit

final class PhysicsHelperTests: XCTestCase {

    private let ground = Ledge(y: 0, minX: 0, maxX: 1000, kind: .ground)
    private let shelf = Ledge(y: 300, minX: 200, maxX: 600, kind: .windowTop)

    func testSupportFoundOnlyWithinLedgeSpan() {
        let ledges = [ground, shelf]
        XCTAssertEqual(PhysicsHelper.support(at: CGPoint(x: 400, y: 300), in: ledges), shelf)
        // По X мимо полки — опоры нет, хотя высота совпадает.
        XCTAssertNil(PhysicsHelper.support(at: CGPoint(x: 800, y: 300), in: ledges))
    }

    func testSupportTolerance() {
        XCTAssertEqual(PhysicsHelper.support(at: CGPoint(x: 10, y: 2), in: [ground]), ground)
        XCTAssertNil(PhysicsHelper.support(at: CGPoint(x: 10, y: 20), in: [ground]))
    }

    func testLandingPicksHighestCrossedLedge() {
        let ledges = [ground, shelf]
        let landed = PhysicsHelper.landing(from: 500, to: -10, x: 400, in: ledges)
        XCTAssertEqual(landed, shelf, "Приземляться нужно на верхнюю из пересечённых полок")
    }

    func testLandingIgnoresUpwardMovement() {
        XCTAssertNil(PhysicsHelper.landing(from: 0, to: 100, x: 400, in: [ground, shelf]))
    }

    func testLandingSkipsLedgeOutsideHorizontalSpan() {
        let landed = PhysicsHelper.landing(from: 500, to: -10, x: 900, in: [ground, shelf])
        XCTAssertEqual(landed, ground, "Полка кончилась по X — падаем мимо неё на пол")
    }

    func testGravityAccelerationIsClamped() {
        var velocity: CGFloat = 0
        var position = CGPoint(x: 0, y: 10_000)
        for _ in 0..<200 {
            let step = PhysicsHelper.applyGravity(position: position, velocityY: velocity, dt: 1.0 / 30)
            position = step.position
            velocity = step.velocityY
        }
        XCTAssertGreaterThanOrEqual(velocity, -PhysicsHelper.maxFallSpeed)
        XCTAssertLessThan(position.y, 10_000)
    }
}
