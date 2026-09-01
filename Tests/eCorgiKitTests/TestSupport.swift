import Foundation
@testable import eCorgiKit

extension SettingsStore {
    /// Настройки для тестов.
    ///
    /// Реакция на курсор выключена намеренно: `CursorTracker` читает настоящее
    /// положение мыши, и если она случайно окажется рядом с тестовой позицией
    /// питомца, тот убежит и тест развалится на ровном месте.
    static func testStore() -> SettingsStore {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "eCorgiTests")!)
        store.reactToCursor = false
        store.windowAwareness = true
        store.speedMultiplier = 1
        store.scale = 1
        return store
    }
}
