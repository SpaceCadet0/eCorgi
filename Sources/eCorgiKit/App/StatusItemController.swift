import AppKit

/// Иконка и меню в строке меню — единственный видимый UI приложения.
final class StatusItemController {

    private let statusItem: NSStatusItem
    private let pet: Pet
    private let preferences: PreferencesWindowController

    private lazy var sleepItem = NSMenuItem(title: "Уложить спать",
                                            action: #selector(toggleSleep),
                                            keyEquivalent: "")

    init(pet: Pet, preferences: PreferencesWindowController) {
        self.pet = pet
        self.preferences = preferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "eCorgi")
            button.image?.isTemplate = true
            if button.image == nil { button.title = "🐕" }
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = menuDelegate

        let call = NSMenuItem(title: "Позвать корги", action: #selector(callPet), keyEquivalent: "")
        call.target = self
        menu.addItem(call)

        sleepItem.target = self
        menu.addItem(sleepItem)

        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "Настройки…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let about = NSMenuItem(title: "О программе", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Выход", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    /// Обновляем заголовок пункта сна прямо перед показом меню.
    private lazy var menuDelegate: MenuDelegate = MenuDelegate { [weak self] in
        guard let self else { return }
        sleepItem.title = pet.isAsleep ? "Разбудить" : "Уложить спать"
    }

    // MARK: - Действия

    @objc private func callPet() {
        // Телепорт к курсору и падение на ближайшую опору.
        pet.position = pet.cursor.location
        pet.velocity = .zero
        pet.force(.fall)
    }

    @objc private func toggleSleep() {
        // И туда, и обратно — через переходные состояния, а не рывком.
        pet.force(pet.isAsleep ? .wakeUp : .settleDown)
    }

    @objc private func openPreferences() {
        preferences.show()
    }

    @objc private func showAbout() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "eCorgi",
            .init(rawValue: "Copyright"): "Настольный корги по мотивам eSheep"
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Маленький адаптер: NSMenuDelegate через замыкание.
final class MenuDelegate: NSObject, NSMenuDelegate {
    private let willOpen: () -> Void
    init(willOpen: @escaping () -> Void) { self.willOpen = willOpen }
    func menuWillOpen(_ menu: NSMenu) { willOpen() }
}
