import AppKit

/// Жизненный цикл приложения: атлас → питомец → окно → игровой цикл.
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private var atlas: SpriteAtlas!
    private var pet: Pet!
    private var windowController: PetWindowController!
    private var statusItem: StatusItemController!
    private var preferences: PreferencesWindowController!
    private var loop: GameLoop!

    private let settings = SettingsStore.shared
    private var appliedScale: Double = 0

    /// Диагностика. `ECORGI_DEBUG=1` — раз в секунду печатает состояние питомца,
    /// `ECORGI_DEBUG=2` — дополнительно выгружает найденную геометрию граней.
    private let debugLevel = Int(ProcessInfo.processInfo.environment["ECORGI_DEBUG"] ?? "0") ?? 0
    private var debugTimer: TimeInterval = 0
    private var dumpedWalls = false
    private var lastBehavior: BehaviorID?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        atlas = SpriteAtlas()
        pet = Pet(atlas: atlas, settings: settings)

        windowController = PetWindowController(pet: pet, atlas: atlas, settings: settings)
        preferences = PreferencesWindowController(settings: settings)
        statusItem = StatusItemController(pet: pet, preferences: preferences)

        appliedScale = settings.scale

        loop = GameLoop { [weak self] dt in self?.tick(dt) }
        loop.start()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(settingsChanged),
                                               name: SettingsStore.didChange,
                                               object: nil)
        ActivationPolicy.observeWindowClosing()
        runWindowSelfCheckIfRequested()
    }

    /// Самопроверка окон: `ECORGI_CHECK_WINDOWS=<папка>` открывает настройки и
    /// «О программе», через две секунды пишет в лог видимые окна и сохраняет
    /// снимок содержимого окна настроек. Своё окно приложение снимает без
    /// разрешения на запись экрана, так что проверять можно без рук.
    private func runWindowSelfCheckIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["ECORGI_CHECK_WINDOWS"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.preferences.show()
            self?.statusItem.showAboutPanel()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            for window in NSApp.windows where window.isVisible {
                NSLog("eCorgi: окно «\(window.title)» \(Int(window.frame.width))x\(Int(window.frame.height)) заголовок=\(window.styleMask.contains(.titled)) класс=\(type(of: window))")
            }
            NSLog("eCorgi: режим \(NSApp.activationPolicy() == .regular ? "обычный" : "строка меню")")
            guard let prefs = NSApp.windows.first(where: { $0.title == "Настройки eCorgi" }),
                  let view = prefs.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                NSLog("eCorgi: окно настроек не найдено"); return
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = URL(fileURLWithPath: dir).appendingPathComponent("preferences.png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            NSLog("eCorgi: снимок настроек \(Int(view.bounds.width))x\(Int(view.bounds.height)) -> \(url.path)")

            // Обратный путь: закрыли одно окно — режим остаётся обычным,
            // закрыли последнее — приложение уходит в строку меню.
            NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) && $0 !== prefs }?.close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSLog("eCorgi: после закрытия «О программе»: \(NSApp.activationPolicy() == .regular ? "обычный" : "строка меню")")
                prefs.close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSLog("eCorgi: после закрытия настроек: \(NSApp.activationPolicy() == .regular ? "обычный" : "строка меню")")
                }
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        loop?.stop()
        windowController?.close()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func tick(_ dt: TimeInterval) {
        pet.update(dt)
        windowController.sync()
        // Сонному питомцу хватает и 10 кадров в секунду — экономим батарею.
        loop.targetFPS = pet.desiredFPS

        guard debugLevel > 0 else { return }

        // Переходы логируем отдельно от периодического среза: короткие
        // состояния (прыжок — доли секунды) иначе проскакивают между замерами.
        if pet.currentBehavior != lastBehavior {
            NSLog("eCorgi: -> \(pet.currentBehavior) в (\(Int(pet.position.x)), \(Int(pet.position.y)))")
            lastBehavior = pet.currentBehavior
        }

        debugTimer += dt
        if debugTimer >= 1 {
            debugTimer = 0
            if debugLevel > 1, !dumpedWalls {
                dumpedWalls = true
                for line in pet.environment.diagnosticReport() { NSLog("eCorgi: \(line)") }
            }
            let reachable = pet.climbableWall() != nil ? "да" : "нет"
            let support = pet.support.map { "\($0.kind) y=\(Int($0.y)) x=\(Int($0.minX))...\(Int($0.maxX))" } ?? "нет"
            NSLog("eCorgi: \(pet.currentBehavior) pos=(\(Int(pet.position.x)), \(Int(pet.position.y))) опора: \(support) полок: \(pet.environment.ledges.count) граней: \(pet.environment.walls.count) грань рядом: \(reachable) актив: \(Int(pet.activeTime))с fps=\(Int(loop.targetFPS))")
        }
    }

    @objc private func settingsChanged() {
        guard settings.scale != appliedScale else { return }
        appliedScale = settings.scale
        windowController.setScale(CGFloat(settings.scale), atlas: atlas)
    }
}
