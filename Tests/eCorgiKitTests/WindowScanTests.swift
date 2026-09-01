import XCTest
@testable import eCorgiKit

/// Отбор окон и построение из них полок и граней.
/// Здесь жил дефект «карабкается на высоту, не связанную с окнами»:
/// перекрытая боковая грань рвалась пополам, и нижний кусок вёл в никуда.
final class WindowScanTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 54, width: 1512, height: 895)   // видимая область
    private let full = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func env() -> ScreenEnvironment {
        ScreenEnvironment(fixedLedges: [], worldBounds: full)
    }

    private func window(_ dict: [String: Any]) -> ScreenEnvironment.WindowVerdict {
        ScreenEnvironment.classify(dict,
                                   ownPID: 999,
                                   primaryMaxY: 982,
                                   minSize: CGSize(width: 120, height: 60),
                                   screenBounds: full,
                                   visibleAreas: [screen])
    }

    /// Словарь в том виде, в каком его отдаёт CGWindowListCopyWindowInfo
    /// (координаты — от левого верхнего угла экрана).
    private func cgWindow(x: CGFloat = 200, y: CGFloat = 100,
                          width: CGFloat = 600, height: CGFloat = 400,
                          layer: Int = 0, alpha: Double = 1, pid: Int32 = 42,
                          owner: String = "Тест") -> [String: Any] {
        [
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowOwnerPID as String: pid,
            kCGWindowOwnerName as String: owner,
            kCGWindowBounds as String: [
                "X": x, "Y": y, "Width": width, "Height": height
            ] as [String: Any]
        ]
    }

    private func accepted(_ verdict: ScreenEnvironment.WindowVerdict) -> ScreenEnvironment.ScannedWindow? {
        guard case .accepted(let window) = verdict else { return nil }
        return window
    }

    // MARK: - Отбор окон

    func testOrdinaryWindowIsAccepted() {
        let scanned = accepted(window(cgWindow()))
        XCTAssertNotNil(scanned)
        // CG считает сверху вниз: верх окна на 100 от верха экрана высотой 982.
        XCTAssertEqual(scanned?.rect.maxY, 882)
        XCTAssertEqual(scanned?.rect.minX, 200)
        XCTAssertEqual(scanned?.isBackdrop, false)
    }

    func testNonApplicationLayersAreRejected() {
        // Строка меню, Dock, «Пункт управления» — на них стоять нельзя.
        XCTAssertNil(accepted(window(cgWindow(layer: 25))))
        XCTAssertNil(accepted(window(cgWindow(layer: -2147483601))))
    }

    func testTransparentTinyAndOwnWindowsAreRejected() {
        XCTAssertNil(accepted(window(cgWindow(alpha: 0))))
        XCTAssertNil(accepted(window(cgWindow(width: 40, height: 30))))
        XCTAssertNil(accepted(window(cgWindow(pid: 999))), "Собственное окно питомца")
    }

    func testWindowOutsideEveryDisplayIsRejected() {
        XCTAssertNil(accepted(window(cgWindow(x: 5000, y: 5000))),
                     "Полка на краю такого окна висела бы в пустоте")
    }

    func testFullScreenWindowIsMarkedAsBackdrop() {
        // Развёрнутое во весь экран окно позади остальных — это фон:
        // его края совпадают с краями экрана, хвататься не за что.
        let scanned = accepted(window(cgWindow(x: 0, y: 33, width: 1512, height: 895)))
        XCTAssertEqual(scanned?.isBackdrop, true)
    }

    func testWindowFillingAlmostAllOfTheScreenIsStillFurniture() {
        let scanned = accepted(window(cgWindow(x: 80, y: 60, width: 1350, height: 800)))
        XCTAssertEqual(scanned?.isBackdrop, false)
    }

    // MARK: - Полки

    func testLedgeIsClippedToTheVisibleArea() {
        let ledges = env().visibleLedges(atY: 500, from: -200, to: 2000, areas: [screen])
        XCTAssertEqual(ledges.count, 1)
        XCTAssertEqual(ledges[0].minX, screen.minX)
        XCTAssertEqual(ledges[0].maxX, screen.maxX)
    }

    func testLedgeAboveTheVisibleAreaIsDropped() {
        // Окно уходит под строку меню — видимой кромки там нет.
        XCTAssertTrue(env().visibleLedges(atY: screen.maxY + 20, from: 100, to: 900, areas: [screen]).isEmpty)
    }

    func testLedgeBelowTheVisibleAreaIsDropped() {
        XCTAssertTrue(env().visibleLedges(atY: screen.minY - 20, from: 100, to: 900, areas: [screen]).isEmpty)
    }

    // MARK: - Грани

    /// Прямоугольник окна и его видимая верхняя грань.
    private func tops(of rect: CGRect) -> [Ledge] {
        [Ledge(y: rect.maxY, minX: rect.minX, maxX: rect.maxX, kind: .windowTop)]
    }

    func testWallReachesTheWindowTop() {
        let rect = CGRect(x: 300, y: 200, width: 500, height: 500)
        let walls = env().climbableWalls(of: rect, inFront: [], leadingTo: tops(of: rect), visibleAreas: [screen])
        XCTAssertEqual(walls.count, 2)
        XCTAssertTrue(walls.allSatisfy { $0.maxY == rect.maxY })
    }

    func testSplitEdgeKeepsOnlyThePieceThatReachesTheTop() {
        // Чужое окно перекрывает середину левой грани и рвёт её надвое.
        // Нижний кусок кончается нижней кромкой чужого окна — лезть туда
        // некуда, и раньше именно он уводил питомца в пустоту.
        let rect = CGRect(x: 300, y: 100, width: 500, height: 600)
        let occluder = CGRect(x: 200, y: 300, width: 400, height: 200)   // накрывает x=300 по y 300…500

        let walls = env().climbableWalls(of: rect, inFront: [occluder],
                                         leadingTo: tops(of: rect), visibleAreas: [screen])
        let left = walls.filter { $0.side == .left }
        XCTAssertEqual(left.count, 1, "Должен остаться ровно один кусок — верхний")
        XCTAssertEqual(left[0].minY, 500, "Он начинается там, где кончается чужое окно")
        XCTAssertEqual(left[0].maxY, rect.maxY, "И доходит до верха своего окна")
    }

    func testEdgeCoveredAtTheTopGivesNoWall() {
        let rect = CGRect(x: 300, y: 100, width: 500, height: 600)
        // Чужое окно накрывает верхнюю часть левой грани.
        let occluder = CGRect(x: 200, y: 500, width: 400, height: 400)

        let left = env().climbableWalls(of: rect, inFront: [occluder],
                                        leadingTo: tops(of: rect), visibleAreas: [screen])
            .filter { $0.side == .left }
        XCTAssertTrue(left.isEmpty, "Верх грани не виден — подниматься по ней бессмысленно")
    }

    func testWallNeedsAVisibleTopLedgeBesideIt() {
        let rect = CGRect(x: 300, y: 200, width: 500, height: 500)
        // Верхняя грань видна только справа — слева хвататься не за что.
        let partialTop = [Ledge(y: rect.maxY, minX: 600, maxX: rect.maxX, kind: .windowTop)]

        let walls = env().climbableWalls(of: rect, inFront: [], leadingTo: partialTop, visibleAreas: [screen])
        XCTAssertEqual(walls.map(\.side), [.right])
    }

    func testWallFlushWithTheScreenSideIsRejected() {
        // Окно прижато к левому краю экрана: видимой кромки там нет.
        let rect = CGRect(x: screen.minX, y: 200, width: 500, height: 500)
        let walls = env().climbableWalls(of: rect, inFront: [], leadingTo: tops(of: rect), visibleAreas: [screen])
        XCTAssertEqual(walls.map(\.side), [.right])
    }

    func testWallShorterThanTheMinimumIsRejected() {
        let rect = CGRect(x: 300, y: 200, width: 500, height: 500)
        let occluder = CGRect(x: 200, y: 200, width: 400, height: 480)   // оставляет сверху щель в 20
        let walls = env().climbableWalls(of: rect, inFront: [occluder],
                                         leadingTo: tops(of: rect), visibleAreas: [screen])
        XCTAssertTrue(walls.filter { $0.side == .left }.isEmpty, "Щель — не лестница")
    }

    func testNoWindowsMeansNoWindowLedges() {
        let environment = ScreenEnvironment(fixedLedges: [Ledge(y: 54, minX: 0, maxX: 1512, kind: .ground)],
                                            worldBounds: full)
        XCTAssertEqual(environment.ledges.filter { $0.kind == .windowTop }.count, 0)
        XCTAssertTrue(environment.walls.isEmpty, "Без окон питомцу остаётся только пол")
    }
}
