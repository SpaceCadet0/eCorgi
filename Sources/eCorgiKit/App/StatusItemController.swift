import AppKit

/// Иконка и меню в строке меню — единственный видимый UI приложения.
final class StatusItemController {

    private let statusItem: NSStatusItem
    private let pet: Pet
    private let preferences: PreferencesWindowController
    private let isPetVisible: () -> Bool
    private let setPetVisible: (Bool) -> Void

    /// Меню целиком — его же показывает правый щелчок по питомцу.
    private(set) var menu = NSMenu()

    /// Строка состояния наверху меню: чем питомец занят и сколько в нём сил.
    private let statusLine: NSMenuItem = {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }()

    private lazy var visibilityItem = NSMenuItem(title: "Спрятать корги",
                                                 action: #selector(toggleVisibility),
                                                 keyEquivalent: "h")

    private lazy var sleepItem = NSMenuItem(title: "Уложить спать",
                                            action: #selector(toggleSleep),
                                            keyEquivalent: "")

    init(pet: Pet,
         preferences: PreferencesWindowController,
         isPetVisible: @escaping () -> Bool = { true },
         setPetVisible: @escaping (Bool) -> Void = { _ in }) {
        self.pet = pet
        self.preferences = preferences
        self.isPetVisible = isPetVisible
        self.setPetVisible = setPetVisible
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "eCorgi")
            button.image?.isTemplate = true
            if button.image == nil { button.title = "🐕" }
            button.toolTip = "eCorgi"
        }
        menu = makeMenu()
        statusItem.menu = menu
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = menuDelegate
        // Пункты включаем и выключаем сами: спрятанного питомца не позвать
        // «спать», а строка состояния не нажимается никогда.
        menu.autoenablesItems = false

        menu.addItem(statusLine)
        menu.addItem(.separator())

        let call = NSMenuItem(title: "Позвать к курсору", action: #selector(callPet), keyEquivalent: "")
        call.target = self
        call.image = symbol("hand.point.up.left")
        menu.addItem(call)

        sleepItem.target = self
        sleepItem.image = symbol("moon.zzz")
        menu.addItem(sleepItem)

        visibilityItem.target = self
        visibilityItem.image = symbol("eye.slash")
        menu.addItem(visibilityItem)

        menu.addItem(.separator())

        let test = NSMenuItem(title: "Проверка анимаций", action: nil, keyEquivalent: "")
        test.submenu = testMenu
        test.image = symbol("film")
        menu.addItem(test)

        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "Настройки…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        prefs.image = symbol("gearshape")
        menu.addItem(prefs)

        let about = NSMenuItem(title: "О программе eCorgi", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        about.image = symbol("info.circle")
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Завершить eCorgi", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    // MARK: - Строка состояния

    /// Чем питомец занят — человеческими словами.
    static func describe(_ behavior: BehaviorID) -> String {
        switch behavior {
        case .idle:          return "Стоит и смотрит по сторонам"
        case .walk:          return "Гуляет"
        case .sit:           return "Присел отдохнуть"
        case .settleDown:    return "Укладывается спать"
        case .sleep:         return "Спит"
        case .wakeUp:        return "Просыпается"
        case .scratch:       return "Чешется"
        case .runFromCursor: return "Удирает от курсора"
        case .climb:         return "Лезет на окно"
        case .hang:          return "Висит на краю окна"
        case .hop:           return "Скачет"
        case .jumpDown:      return "Спрыгивает с окна"
        case .fall:          return "Падает"
        case .land:          return "Приземлился"
        case .drag:          return "У вас в руках"
        }
    }

    /// Сколько сил осталось до сна, 0…100.
    static func energyPercent(activeTime: TimeInterval, limit: TimeInterval) -> Int {
        guard limit > 0 else { return 100 }
        return Int(((1 - activeTime / limit).clamped(to: 0...1) * 100).rounded())
    }

    private func refreshStatus() {
        let visible = isPetVisible()
        if !visible {
            statusLine.title = "Корги спрятан"
        } else if pet.previewBehavior != nil {
            statusLine.title = "Показывает анимацию"
        } else {
            let energy = StatusItemController.energyPercent(activeTime: pet.activeTime,
                                                            limit: pet.tuning.sleepAfterActivity)
            statusLine.title = "\(StatusItemController.describe(pet.currentBehavior)) · бодрость \(energy)%"
        }
        visibilityItem.title = visible ? "Спрятать корги" : "Показать корги"
        visibilityItem.image = symbol(visible ? "eye.slash" : "eye")
        sleepItem.title = pet.isAsleep ? "Разбудить" : "Уложить спать"
        sleepItem.image = symbol(pet.isAsleep ? "sun.max" : "moon.zzz")
        sleepItem.isEnabled = visible && pet.previewBehavior == nil
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
        refreshStatus()
        refreshTestMenu()
    }

    // MARK: - Действия

    @objc private func toggleVisibility() {
        setPetVisible(!isPetVisible())
    }

    @objc private func callPet() {
        // Позвать можно и спрятанного, и занятого показом анимации.
        setPetVisible(true)
        pet.previewBehavior = nil
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
        showAboutPanel()
    }

    func showAboutPanel() {
        ActivationPolicy.enterRegularMode()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "eCorgi",
            .credits: NSAttributedString(
                string: "Корги, который живёт на рабочем столе: гуляет по окнам, спит, удирает от курсора и даётся в руки.",
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                             .foregroundColor: NSColor.secondaryLabelColor]),
            .init(rawValue: "Copyright"): "По мотивам eSheep"
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
