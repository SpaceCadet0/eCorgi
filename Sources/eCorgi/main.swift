import AppKit
import eCorgiKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Без иконки в Dock и без пункта в переключателе приложений (аналог LSUIElement).
application.setActivationPolicy(.accessory)
application.run()
