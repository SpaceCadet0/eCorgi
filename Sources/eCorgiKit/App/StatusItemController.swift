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

        let test = NSMenuItem(title: "Тест", action: nil, keyEquivalent: "")
        test.submenu = testMenu
        menu.addItem(test)

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

    // MARK: - Проверка анимаций

    /// Поведения в порядке, удобном для просмотра: сначала обычная жизнь,
    /// потом оконная акробатика, потом всё, что связано с руками и падением.
    static let testable: [(BehaviorID, String)] = [
        (.idle, "Стоит"),
        (.walk, "Идёт"),
        (.runFromCursor, "Убегает"),
        (.scratch, "Чешется"),
        (.sit, "Сидит"),
        (.settleDown, "Укладывается"),
        (.sleep, "Спит"),
        (.wakeUp, "Просыпается"),
        (.climb, "Лезет по грани"),
        (.hang, "Висит на грани"),
        (.hop, "Подскакивает"),
        (.jumpDown, "Спрыгивает"),
        (.fall, "Падает"),
        (.land, "Приземляется"),
        (.drag, "В руках")
    ]

    /// Пункт «Обычная жизнь» и пункты поведений держим ссылками, а не ищем
    /// по тегам: у пунктов меню тег по умолчанию нулевой, и поиск по нулю
    /// находил бы не то поведение.
    private var liveItem: NSMenuItem?
    private var behaviourItems: [NSMenuItem] = []

    private lazy var testMenu: NSMenu = {
        let menu = NSMenu()

        let live = NSMenuItem(title: "Обычная жизнь", action: #selector(stopTesting), keyEquivalent: "")
        live.target = self
        menu.addItem(live)
        liveItem = live
        menu.addItem(.separator())

        for (index, entry) in StatusItemController.testable.enumerated() {
            let item = NSMenuItem(title: entry.1, action: #selector(playBehavior(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
            behaviourItems.append(item)
        }
        return menu
    }()

    /// Заголовки собираются перед показом: пак меняется на ходу, и полезно
    /// видеть прямо в меню, своими ли кадрами показывается поведение.
    private func refreshTestMenu() {
        _ = testMenu
        liveItem?.state = pet.previewBehavior == nil ? .on : .off

        for (index, entry) in StatusItemController.testable.enumerated() {
            guard index < behaviourItems.count else { break }
            let item = behaviourItems[index]
            let wanted = Pet.animations[entry.0]?.action ?? .idle
            let source = pet.atlas.source(for: wanted)
            let detail = source.action == wanted
                ? "\(wanted.rawValue), \(source.frames)"
                : "\(wanted.rawValue) → \(source.action.rawValue), \(source.frames)"
            item.title = "\(entry.1) — \(detail)"
            item.state = pet.previewBehavior == entry.0 ? .on : .off
        }
    }

    @objc private func playBehavior(_ sender: NSMenuItem) {
        guard StatusItemController.testable.indices.contains(sender.tag) else { return }
        pet.previewBehavior = StatusItemController.testable[sender.tag].0
    }

    @objc private func stopTesting() {
        pet.previewBehavior = nil
    }

    /// Обновляем заголовок пункта сна прямо перед показом меню.
    private lazy var menuDelegate: MenuDelegate = MenuDelegate { [weak self] in
        guard let self else { return }
        sleepItem.title = pet.isAsleep ? "Разбудить" : "Уложить спать"
        refreshTestMenu()
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
