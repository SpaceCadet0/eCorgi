import Foundation

/// Обёртка над UserDefaults. Изменения рассылаются через NotificationCenter,
/// чтобы окно питомца и движок подхватывали их без прямых ссылок на UI.
public final class SettingsStore {

    public static let didChange = Notification.Name("eCorgi.settingsDidChange")
    public static let shared = SettingsStore()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.speed: 1.0,
            Key.scale: 1.0,
            Key.reactToCursor: true,
            Key.windowAwareness: true,
            Key.soundEnabled: false,
            Key.launchAtLogin: false
        ])
    }

    private enum Key {
        static let speed = "speedMultiplier"
        static let scale = "spriteScale"
        static let reactToCursor = "reactToCursor"
        static let windowAwareness = "windowAwareness"
        static let soundEnabled = "soundEnabled"
        static let launchAtLogin = "launchAtLogin"
    }

    /// Множитель скорости движения и темпа анимации, 0.5…2.
    public var speedMultiplier: Double {
        get { defaults.double(forKey: Key.speed) }
        set { set(newValue.clamped(to: 0.5...2), forKey: Key.speed) }
    }

    /// Масштаб спрайта, 0.5…2.
    public var scale: Double {
        get { defaults.double(forKey: Key.scale) }
        set { set(newValue.clamped(to: 0.5...2), forKey: Key.scale) }
    }

    public var reactToCursor: Bool {
        get { defaults.bool(forKey: Key.reactToCursor) }
        set { set(newValue, forKey: Key.reactToCursor) }
    }

    /// Ходить ли по верхним краям чужих окон.
    public var windowAwareness: Bool {
        get { defaults.bool(forKey: Key.windowAwareness) }
        set { set(newValue, forKey: Key.windowAwareness) }
    }

    public var soundEnabled: Bool {
        get { defaults.bool(forKey: Key.soundEnabled) }
        set { set(newValue, forKey: Key.soundEnabled) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { set(newValue, forKey: Key.launchAtLogin) }
    }

    private func set(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: SettingsStore.didChange, object: self)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
