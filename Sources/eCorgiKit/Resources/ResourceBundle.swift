import Foundation

/// Поиск ресурсного бандла SPM.
///
/// Сгенерированный `Bundle.module` ищет бандл строго рядом с `Bundle.main.bundleURL`,
/// а внутри `.app` это корень пакета — класть туда ресурсы нельзя, подпись и
/// нотаризация такого не примут. Поэтому свой резолвер: он проверяет и
/// `Contents/Resources` собранного приложения, и папку сборки `swift run`.
enum ResourceBundle {

    private static let bundleName = "eCorgi_eCorgiKit.bundle"

    static let current: Bundle = {
        let module = Bundle(for: SpriteAtlas.self)
        let candidates: [URL?] = [
            Bundle.main.resourceURL,                       // eCorgi.app/Contents/Resources
            Bundle.main.bundleURL,                         // рядом с бинарником (swift run)
            module.resourceURL,
            module.bundleURL.deletingLastPathComponent()
        ]
        for base in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: base.appendingPathComponent(bundleName)) { return bundle }
        }
        return module
    }()

    static func url(forResource name: String, withExtension ext: String?) -> URL? {
        current.url(forResource: name, withExtension: ext)
    }
}
