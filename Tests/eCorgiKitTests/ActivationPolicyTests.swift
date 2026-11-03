import XCTest
@testable import eCorgiKit

/// Когда приложению нужен обычный режим с иконкой в Dock.
final class ActivationPolicyTests: XCTestCase {

    private final class Token {}
    private let pet = Token(), settings = Token(), about = Token()

    private func info(_ t: Token, visible: Bool = true, titled: Bool) -> ActivationPolicy.WindowInfo {
        .init(id: ObjectIdentifier(t), isVisible: visible, isTitled: titled)
    }

    func testOnlyThePetWindowMeansMenuBarMode() {
        XCTAssertFalse(ActivationPolicy.needsRegularMode([info(pet, titled: false)], closing: nil))
    }

    func testOpenSettingsKeepRegularMode() {
        XCTAssertTrue(ActivationPolicy.needsRegularMode([info(pet, titled: false), info(settings, titled: true)],
                                                        closing: nil))
    }

    func testClosingTheLastTitledWindowReturnsToMenuBar() {
        XCTAssertFalse(ActivationPolicy.needsRegularMode([info(pet, titled: false), info(settings, titled: true)],
                                                         closing: ObjectIdentifier(settings)))
    }

    func testAboutPanelStillOpenKeepsRegularMode() {
        // Закрыли настройки, но «О программе» ещё открыто — режим остаётся.
        let windows = [info(pet, titled: false), info(settings, titled: true), info(about, titled: true)]
        XCTAssertTrue(ActivationPolicy.needsRegularMode(windows, closing: ObjectIdentifier(settings)))
    }

    func testHiddenWindowsDoNotCount() {
        XCTAssertFalse(ActivationPolicy.needsRegularMode([info(settings, visible: false, titled: true)],
                                                         closing: nil))
    }
}
