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
        preferences.hideIfNeeded()
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
