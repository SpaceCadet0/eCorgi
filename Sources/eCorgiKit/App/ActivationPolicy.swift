import AppKit

/// Когда приложению нужна иконка в Dock.
///
/// eCorgi живёт в строке меню (`.accessory`), но окна настроек и «О программе»
/// требуют обычного режима: панель «О программе» прячется, как только
/// приложение теряет активность. Поэтому режим меняется по событиям — открыли
/// окно или закрыли его, — а не на каждом тике: прежняя проверка 30 раз в
/// секунду возвращала `.accessory`, и панель гасла сразу после открытия.
enum ActivationPolicy {

    /// Что нужно знать об окне, чтобы решить, держит ли оно обычный режим.
    struct WindowInfo {
        let id: ObjectIdentifier
        let isVisible: Bool
        /// Окно с заголовком. Окно питомца, строка меню и меню без заголовка.
        let isTitled: Bool
    }

    /// Остаётся ли видимое окно с заголовком, кроме закрывающегося.
    static func needsRegularMode(_ windows: [WindowInfo], closing: ObjectIdentifier?) -> Bool {
        windows.contains { $0.isVisible && $0.isTitled && $0.id != closing }
    }

    static func info(_ window: NSWindow) -> WindowInfo {
        WindowInfo(id: ObjectIdentifier(window), isVisible: window.isVisible,
                   isTitled: window.styleMask.contains(.titled))
    }

    /// Показать окно приложения: перейти в обычный режим и вывести вперёд.
    static func enterRegularMode() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Следить за закрытием окон и возвращаться в строку меню, когда последнее
    /// окно с заголовком закрыто.
    static func observeWindowClosing() {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: nil, queue: .main) { note in
            let closing = (note.object as? NSWindow).map(ObjectIdentifier.init)
            let windows = NSApp.windows.map(info)
            guard !needsRegularMode(windows, closing: closing) else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
