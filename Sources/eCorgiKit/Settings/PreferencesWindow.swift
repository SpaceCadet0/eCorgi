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
        // Показываем то, что есть на самом деле: автозапуск могли выключить
        // в Системных настройках, и сохранённый флажок тогда врёт.
        _launchAtLogin = State(initialValue: LoginItem.isEnabled ?? settings.launchAtLogin)
    }

    var body: some View {
        Form {
            Section {
                slider(title: "Темп", value: $speed, low: "tortoise", high: "hare",
                       hint: "Скорость движения и анимации") { settings.speedMultiplier = $0 }
                slider(title: "Размер", value: $scale, low: "minus.magnifyingglass", high: "plus.magnifyingglass",
                       hint: "Резче всего корги выглядит при 1× и 2×") { settings.scale = $0 }
            } header: {
                Text("Внешность")
            }

            Section {
                Toggle(isOn: $reactToCursor) {
                    label("Убегать от курсора", hint: "Спящего корги мышь не будит")
                }
                .onChange(of: reactToCursor) { settings.reactToCursor = $0 }

                Toggle(isOn: $windowAwareness) {
                    label("Гулять по окнам", hint: "Забирается на переднее окно, висит на краю и спрыгивает")
                }
                .onChange(of: windowAwareness) { settings.windowAwareness = $0 }
            } header: {
                Text("Характер")
            }

            Section {
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        settings.launchAtLogin = enabled
                        LoginItem.setEnabled(enabled)
                    }
            } header: {
                Text("Система")
            } footer: {
                HStack {
                    Spacer()
                    Button("Вернуть как было", action: reset)
                        .disabled(isDefault)
                }
                .padding(.top, 6)
            }
        }
        .formStyle(.grouped)
        // Явный размер: без высоты сгруппированная форма в NSHostingController
        // сообщала окну нулевой контент, и окно открывалось пустым.
        .frame(width: PreferencesView.size.width, height: PreferencesView.size.height)
    }

    static let size = CGSize(width: 400, height: 540)

    private var isDefault: Bool {
        speed == 1 && scale == 1 && reactToCursor && windowAwareness
    }

    /// Автозапуск сбросом не трогаем: это решение про систему, а не про корги.
    private func reset() {
        speed = 1
        scale = 1
        reactToCursor = true
        windowAwareness = true
    }

    private func slider(title: String, value: Binding<Double>, low: String, high: String,
                        hint: String, apply: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.1f")×")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0.5...2, step: 0.1) {
                EmptyView()
            } minimumValueLabel: {
                Image(systemName: low).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: high).foregroundStyle(.secondary)
            }
            .onChange(of: value.wrappedValue, perform: apply)
            .accessibilityLabel(title)
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func label(_ title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Регистрация в автозапуске. Работает только для собранного .app-бандла,
/// поэтому при запуске из `swift run` молча ничего не делает.
enum LoginItem {
    /// Включён ли автозапуск по данным системы; `nil` вне .app-бандла.
    static var isEnabled: Bool? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return SMAppService.mainApp.status == .enabled
    }

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
    private var hasBeenShown = false
    private let settings: SettingsStore

    init(settings: SettingsStore) { self.settings = settings }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PreferencesView(settings: settings))
            hosting.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hosting)
            window.setContentSize(PreferencesView.size)
            window.title = "Настройки eCorgi"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            self.window = window
        }
        ActivationPolicy.enterRegularMode()
        // Центрируем только при первом показе: дальше окно остаётся там,
        // куда его передвинули.
        if window?.isVisible == false, !hasBeenShown { window?.center() }
        hasBeenShown = true
        window?.makeKeyAndOrderFront(nil)
    }

}
