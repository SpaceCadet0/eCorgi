import AppKit
import SwiftUI
import ServiceManagement

/// Окно настроек. Здесь SwiftUI уместен: обычное окно, никакой возни
/// с прозрачностью и Z-order, в отличие от окна питомца.
struct PreferencesView: View {

    @State private var speed: Double
    @State private var scale: Double
    @State private var reactToCursor: Bool
    @State private var windowAwareness: Bool
    @State private var launchAtLogin: Bool

    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        _speed = State(initialValue: settings.speedMultiplier)
        _scale = State(initialValue: settings.scale)
        _reactToCursor = State(initialValue: settings.reactToCursor)
        _windowAwareness = State(initialValue: settings.windowAwareness)
        _launchAtLogin = State(initialValue: settings.launchAtLogin)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    Text("Скорость: \(speed, specifier: "%.1f")×")
                    Slider(value: $speed, in: 0.5...2, step: 0.1)
                        .onChange(of: speed) { settings.speedMultiplier = $0 }
                }
                VStack(alignment: .leading) {
                    Text("Размер: \(scale, specifier: "%.1f")×")
                    Slider(value: $scale, in: 0.5...2, step: 0.1)
                        .onChange(of: scale) { settings.scale = $0 }
                }
            }

            Section {
                Toggle("Убегать от курсора", isOn: $reactToCursor)
                    .onChange(of: reactToCursor) { settings.reactToCursor = $0 }
                Toggle("Ходить по краям окон", isOn: $windowAwareness)
                    .onChange(of: windowAwareness) { settings.windowAwareness = $0 }
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        settings.launchAtLogin = enabled
                        LoginItem.setEnabled(enabled)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .padding(.vertical, 8)
    }
}

/// Регистрация в автозапуске. Работает только для собранного .app-бандла,
/// поэтому при запуске из `swift run` молча ничего не делает.
enum LoginItem {
    static func setEnabled(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("eCorgi: не удалось изменить автозапуск — \(error.localizedDescription)")
        }
    }
}

/// Держатель окна настроек — одно на всё приложение.
final class PreferencesWindowController {

    private var window: NSWindow?
    private let settings: SettingsStore

    init(settings: SettingsStore) { self.settings = settings }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PreferencesView(settings: settings))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Настройки eCorgi"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Возврат в режим «только строка меню» после закрытия настроек.
    func hideIfNeeded() {
        guard window?.isVisible != true else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
