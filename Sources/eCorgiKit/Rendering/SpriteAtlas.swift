import AppKit

/// Действие персонажа. Совпадает с префиксом имени файла спрайта:
/// `<action>_<frame>.png`, например `walk_00.png`, `sit_down_02.png`.
public enum SpriteAction: String, CaseIterable, Sendable {
    case idle
    case walk
    case run
    case sit
    case sitDown = "sit_down"
    case standUp = "stand_up"
    case sleep
    case climb
    case hang
    case fall
    case land
    case drag
    case scratch
    case bark
    case jump
}

/// Загрузка и кэш кадров. Пока спрайт-пак не готов, недостающие действия
/// подменяются по цепочке фолбэков, чтобы движок можно было отлаживать
/// на неполном наборе кадров (сейчас — на кадрах бега кабана).
public final class SpriteAtlas {

    /// Кадры действия в порядке воспроизведения.
    private var frames: [SpriteAction: [SpriteFrame]] = [:]
    /// Результат разрешения фолбэков, чтобы не проходить цепочку каждый кадр.
    private var resolved: [SpriteAction: [SpriteFrame]] = [:]

    /// Максимальный размер кадра по всему атласу — по нему подбирается
    /// размер окна питомца, чтобы оно не «дышало» при смене кадра.
    public private(set) var maxFrameSize: CGSize = .zero

    public init(directory: URL? = nil) {
        let dir = directory ?? ResourceBundle.url(forResource: "Sprites", withExtension: nil)
        if let dir { load(from: dir) }
        if frames.isEmpty { frames[.idle] = [SpriteAtlas.placeholderFrame()] }
        recomputeMaxFrameSize()
    }

    // MARK: - Загрузка

    private func load(from directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var buckets: [SpriteAction: [(index: Int, url: URL)]] = [:]
        var ignored: [String] = []

        for url in files where url.pathExtension.lowercased() == "png" {
            let name = url.deletingPathExtension().lastPathComponent
            guard let parsed = SpriteAtlas.parse(fileName: name) else {
                ignored.append(name)
                continue
            }
            buckets[parsed.action, default: []].append((parsed.index, url))
        }

        for (action, items) in buckets {
            let images = items
                // При совпадении номеров (например `idle_00` и `idle_000`)
                // порядок задаётся именем файла, иначе он был бы случайным.
                .sorted { ($0.index, $0.url.lastPathComponent) < ($1.index, $1.url.lastPathComponent) }
                .compactMap { NSImage(contentsOf: $0.url) }
                .compactMap { SpriteFrame(nsImage: $0) }
            if !images.isEmpty { frames[action] = images }
        }

        // Файл, названный не по схеме `<действие>_<кадр>.png`, молча выпадал бы
        // из анимации — а это самая частая ошибка при заводе спрайт-пака.
        if !ignored.isEmpty {
            NSLog("eCorgi: пропущено кадров с неизвестным действием — \(ignored.count): \(ignored.sorted().prefix(6).joined(separator: ", "))")
        }
    }

    /// `walk_07` -> (.walk, 7). Номер кадра — всё после последнего `_`.
    static func parse(fileName: String) -> (action: SpriteAction, index: Int)? {
        guard let separator = fileName.lastIndex(of: "_") else { return nil }
        let name = String(fileName[fileName.startIndex..<separator])
        let number = String(fileName[fileName.index(after: separator)...])
        guard let index = Int(number), let action = SpriteAction(rawValue: name) else { return nil }
        return (action, index)
    }

    private func recomputeMaxFrameSize() {
        var size = CGSize.zero
        for images in frames.values {
            for frame in images {
                size.width = max(size.width, frame.size.width)
                size.height = max(size.height, frame.size.height)
            }
        }
        maxFrameSize = size == .zero ? CGSize(width: 64, height: 64) : size
    }

    // MARK: - Доступ к кадрам

    /// Кадры действия с учётом фолбэков. Всегда возвращает непустой массив.
    public func frames(for action: SpriteAction) -> [SpriteFrame] {
        if let cached = resolved[action] { return cached }

        var images: [SpriteFrame] = []
        for candidate in SpriteAtlas.fallbackChain(for: action) {
            if let found = frames[candidate], !found.isEmpty { images = found; break }
        }
        if images.isEmpty { images = frames.values.first(where: { !$0.isEmpty }) ?? [SpriteAtlas.placeholderFrame()] }

        resolved[action] = images
        return images
    }

    /// Откуда действие реально берёт кадры и сколько их.
    /// Если пак неполон, это будет не само действие, а его подмена —
    /// меню проверки показывает это прямо в пункте.
    public func source(for action: SpriteAction) -> (action: SpriteAction, frames: Int) {
        for candidate in SpriteAtlas.fallbackChain(for: action) {
            if let found = frames[candidate], !found.isEmpty { return (candidate, found.count) }
        }
        return (action, frames(for: action).count)
    }

    /// Есть ли для действия собственные кадры (без подмены).
    public func hasOwnFrames(for action: SpriteAction) -> Bool {
        frames[action]?.isEmpty == false
    }

    /// Цепочка подмены: первый элемент — само действие.
    static func fallbackChain(for action: SpriteAction) -> [SpriteAction] {
        switch action {
        case .idle:     return [.idle, .sit, .walk]
        case .walk:     return [.walk, .run, .idle]
        case .run:      return [.run, .walk, .idle]
        case .sit:      return [.sit, .idle, .walk]
        case .sitDown:  return [.sitDown, .sit, .idle, .walk]
        case .standUp:  return [.standUp, .sit, .idle, .walk]
        case .sleep:    return [.sleep, .sit, .idle, .walk]
        case .climb:    return [.climb, .walk, .idle]
        case .hang:     return [.hang, .idle, .walk]
        case .fall:     return [.fall, .jump, .idle, .walk]
        case .land:     return [.land, .sit, .idle, .walk]
        case .drag:     return [.drag, .fall, .idle, .walk]
        case .scratch:  return [.scratch, .sit, .idle, .walk]
        case .bark:     return [.bark, .idle, .walk]
        case .jump:     return [.jump, .run, .walk, .idle]
        }
    }

    /// Аварийный кадр на случай полностью пустой папки спрайтов —
    /// приложение всё равно должно что-то показывать.
    static func placeholderFrame() -> SpriteFrame {
        let size = CGSize(width: 64, height: 48)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: 10, yRadius: 10).fill()
        image.unlockFocus()
        return SpriteFrame(nsImage: image) ?? SpriteFrame(image: SpriteAtlas.blankCGImage(), size: size)
    }

    private static func blankCGImage() -> CGImage {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }
}
