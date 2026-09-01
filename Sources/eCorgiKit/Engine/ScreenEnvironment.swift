import AppKit

/// Сбор геометрии «мира»: экраны и верхние грани чужих окон.
///
/// `CGWindowListCopyWindowInfo` — самый дорогой вызов во всём тике (XPC в
/// оконный сервер плюс разбор property list), поэтому он вынесен на фоновую
/// очередь, а частота опроса зависит от того, чем питомец сейчас занят.
/// Мутируется `ledges` при этом только на главном потоке.
public final class ScreenEnvironment {

    /// Насколько срочно питомцу нужна свежая геометрия окон.
    public enum Urgency {
        case low     // сидит или спит на полу — окна почти не важны
        case normal  // ходит
        case high    // падает или его тащат: нужна точная опора

        var interval: TimeInterval {
            switch self {
            case .low:    return 1.5
            case .normal: return 0.5
            case .high:   return 0.15
            }
        }
    }

    /// Учитывать ли окна других приложений как «полки».
    public var windowAwareness: Bool = true

    public private(set) var ledges: [Ledge] = []
    /// Вертикальные грани окон — по ним питомец залезает наверх.
    public private(set) var walls: [Wall] = []
    /// Объединённая видимая область всех экранов — для ограничения перемещения.
    public private(set) var worldBounds: CGRect = .zero

    private var groundCache: [Ledge] = []
    private var windowCache: [Ledge] = []
    private var wallCache: [Wall] = []

    private var timeSinceRefresh: TimeInterval = .greatestFiniteMagnitude
    private var isScanning = false

    private let scanQueue = DispatchQueue(label: "com.ecorgi.window-scan", qos: .utility)
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Окна меньше этого размера считаем декоративными (тултипы, тени, панельки).
    private let minWindowSize = CGSize(width: 120, height: 60)
    /// Огрызок грани короче этого лезть не стоит — это щель между чужими окнами.
    private let minWallHeight: CGFloat = 70

    /// Зафиксированная геометрия: среда не обращается к системе.
    /// Нужна тестам и режиму «только пол экрана».
    private let isStatic: Bool

    public init() {
        isStatic = false
        refresh()
    }

    public init(fixedLedges: [Ledge], fixedWalls: [Wall] = [], worldBounds: CGRect) {
        isStatic = true
        self.windowAwareness = false
        self.groundCache = fixedLedges
        self.windowCache = []
        self.wallCache = fixedWalls
        self.ledges = fixedLedges
        self.walls = fixedWalls
        self.worldBounds = worldBounds
    }

    // MARK: - Тик

    public func update(_ dt: TimeInterval, urgency: Urgency = .normal) {
        guard !isStatic else { return }
        timeSinceRefresh += dt
        guard timeSinceRefresh >= urgency.interval else { return }
        timeSinceRefresh = 0

        refreshScreens()

        guard windowAwareness else {
            windowCache = []
            wallCache = []
            rebuild()
            return
        }
        scanWindowsAsync()
    }

    /// Синхронная пересборка — для старта и тестов.
    public func refresh() {
        guard !isStatic else { return }
        refreshScreens()
        let scan: (ledges: [Ledge], walls: [Wall]) =
            windowAwareness ? scanWindows(screenGeometry) : (ledges: [], walls: [])
        windowCache = scan.ledges
        wallCache = scan.walls
        rebuild()
    }

    // MARK: - Экраны

    /// Геометрия экранов, снятая на главном потоке: фоновый скан не имеет
    /// права трогать NSScreen, поэтому получает всё нужное готовым.
    struct ScreenGeometry {
        /// Высота экрана, задающего начало координат.
        let primaryMaxY: CGFloat
        /// Объединение полных областей всех дисплеев.
        let fullBounds: CGRect
        /// Видимые области экранов — без строки меню и Dock.
        let visibleAreas: [CGRect]
    }

    private var screenGeometry: ScreenGeometry {
        ScreenGeometry(primaryMaxY: primaryMaxY,
                       fullBounds: screenBounds,
                       visibleAreas: NSScreen.screens.map(\.visibleFrame))
    }

    /// Высота экрана, задающего начало координат. CoreGraphics отсчитывает
    /// от его левого верхнего угла, AppKit — от левого нижнего.
    private var primaryMaxY: CGFloat {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        return primary?.frame.maxY ?? 0
    }

    /// Объединение полных областей экранов — по нему отсеиваются окна,
    /// уехавшие за пределы всех дисплеев.
    private var screenBounds: CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    private func refreshScreens() {
        groundCache = NSScreen.screens.map { screen in
            let frame = screen.visibleFrame
            return Ledge(y: frame.minY, minX: frame.minX, maxX: frame.maxX, kind: .ground)
        }
        worldBounds = NSScreen.screens.reduce(CGRect.null) { $0.union($1.visibleFrame) }
    }

    private func rebuild() {
        ledges = groundCache + windowCache
        walls = wallCache
    }

    /// Экран, на котором сейчас находится точка (или главный, если точка вне экранов).
    public func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    // MARK: - Верхние грани чужих окон

    private func scanWindowsAsync() {
        guard !isScanning else { return }
        isScanning = true
        // NSScreen — главнопоточный API, поэтому геометрию экранов считаем
        // здесь и передаём в фоновую задачу готовыми числами.
        let geometry = screenGeometry
        scanQueue.async { [weak self] in
            guard let self else { return }
            let scanned = self.scanWindows(geometry)
            DispatchQueue.main.async {
                self.windowCache = self.windowAwareness ? scanned.ledges : []
                self.wallCache = self.windowAwareness ? scanned.walls : []
                self.rebuild()
                self.isScanning = false
            }
        }
    }

    /// Окно, прошедшее отбор: прямоугольник в координатах AppKit плюс
    /// сведения для диагностики.
    struct ScannedWindow {
        let rect: CGRect
        let owner: String
        /// Окно занимает всю видимую область экрана.
        ///
        /// Его края совпадают с краями экрана, так что видимой кромки, за
        /// которую можно взяться, там нет: развёрнутое во весь экран окно
        /// позади остальных читается как фон. Полок и граней такое окно не
        /// даёт, но чужие окна собой по-прежнему закрывает.
        let isBackdrop: Bool
    }

    /// Итог проверки одного окна. Причина отказа нужна не движку, а
    /// диагностике: без неё непонятно, откуда берутся лишние полки.
    enum WindowVerdict {
        case accepted(ScannedWindow)
        case rejected(owner: String, reason: String)
    }

    /// Годится ли окно в опору.
    ///
    /// Вынесено отдельно и без обращения к системе — так фильтр можно
    /// проверить тестами на синтетических словарях и показать в диагностике.
    static func classify(_ window: [String: Any],
                         ownPID: Int32,
                         primaryMaxY: CGFloat,
                         minSize: CGSize,
                         screenBounds: CGRect,
                         visibleAreas: [CGRect] = []) -> WindowVerdict {
        let owner = window[kCGWindowOwnerName as String] as? String ?? "?"

        guard let layer = window[kCGWindowLayer as String] as? Int else {
            return .rejected(owner: owner, reason: "нет слоя")
        }
        // Слой 0 — обычные окна приложений. Всё остальное это панели,
        // подсказки, оверлеи системы: стоять на них нельзя.
        guard layer == 0 else { return .rejected(owner: owner, reason: "слой \(layer)") }

        let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
        guard alpha > 0.1 else { return .rejected(owner: owner, reason: "прозрачное") }

        guard let pid = window[kCGWindowOwnerPID as String] as? Int32 else {
            return .rejected(owner: owner, reason: "нет pid")
        }
        guard pid != ownPID else { return .rejected(owner: owner, reason: "наше окно") }

        guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
              let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
            return .rejected(owner: owner, reason: "нет границ")
        }
        guard cgRect.width >= minSize.width, cgRect.height >= minSize.height else {
            return .rejected(owner: owner, reason: "мелкое \(Int(cgRect.width))x\(Int(cgRect.height))")
        }

        let rect = convertToAppKit(cgRect, primaryMaxY: primaryMaxY)
        // Окно может лежать за пределами экранов — например, уехало на другой
        // дисплей, который отключили. Полка на его краю висела бы в пустоте.
        guard screenBounds.isNull || rect.intersects(screenBounds) else {
            return .rejected(owner: owner, reason: "вне экранов")
        }
        let isBackdrop = visibleAreas.contains { fills($0, with: rect) }
        return .accepted(ScannedWindow(rect: rect, owner: owner, isBackdrop: isBackdrop))
    }

    /// Занимает ли окно видимую область экрана целиком (с небольшим допуском).
    static func fills(_ area: CGRect, with rect: CGRect, tolerance: CGFloat = 4) -> Bool {
        rect.minX <= area.minX + tolerance
            && rect.maxX >= area.maxX - tolerance
            && rect.minY <= area.minY + tolerance
            && rect.maxY >= area.maxY - tolerance
    }

    private func acceptedWindows(_ geometry: ScreenGeometry) -> [ScannedWindow] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        guard let windows = info as? [[String: Any]] else { return [] }
        return windows.compactMap {
            guard case .accepted(let window) = ScreenEnvironment.classify($0,
                                                                          ownPID: ownPID,
                                                                          primaryMaxY: geometry.primaryMaxY,
                                                                          minSize: minWindowSize,
                                                                          screenBounds: geometry.fullBounds,
                                                                          visibleAreas: geometry.visibleAreas)
            else { return nil }
            return window
        }
    }

    private func scanWindows(_ geometry: ScreenGeometry) -> (ledges: [Ledge], walls: [Wall]) {
        // Список идёт спереди назад — это и есть порядок перекрытия.
        let windows = acceptedWindows(geometry)
        let rects = windows.map(\.rect)

        var ledges: [Ledge] = []
        var walls: [Wall] = []

        for (index, window) in windows.enumerated() {
            let rect = window.rect
            // Фон в перекрытии участвует, но собственных полок не даёт.
            let inFront = rects[0..<index]
            guard !window.isBackdrop else { continue }

            // Верхнюю грань обрезаем окнами, которые лежат перед ней и накрывают её высоту.
            let topOccluders = inFront.filter { $0.minY < rect.maxY && $0.maxY > rect.maxY - 1 }
            let topSegments = ScreenEnvironment.subtract(topOccluders.map { ($0.minX, $0.maxX) },
                                                         from: (rect.minX, rect.maxX))

            let ownTop = topSegments.flatMap {
                visibleLedges(atY: rect.maxY, from: $0.0, to: $0.1, areas: geometry.visibleAreas)
            }
            ledges.append(contentsOf: ownTop)

            walls.append(contentsOf: climbableWalls(of: rect, inFront: inFront,
                                                    leadingTo: ownTop,
                                                    visibleAreas: geometry.visibleAreas))
        }
        return (ledges, walls)
    }

    /// Совпадает ли вертикаль с боковой границей видимой области экрана.
    static func isFlushWithSide(_ x: CGFloat, of area: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(x - area.minX) <= tolerance || abs(x - area.maxX) <= tolerance
    }

    /// Кусок верхней грани окна, обрезанный по видимой области экранов.
    ///
    /// Окно может уходить под строку меню или за Dock — там его край
    /// пользователю не виден, и полка на нём выглядит как ходьба по воздуху.
    /// Развёрнутое во весь экран окно позади всех остальных давало ровно это:
    /// дорожку через весь экран поверх строки меню.
    func visibleLedges(atY y: CGFloat, from minX: CGFloat, to maxX: CGFloat,
                               areas: [CGRect]) -> [Ledge] {
        areas.compactMap { area in
            guard y >= area.minY, y <= area.maxY else { return nil }
            let left = max(minX, area.minX)
            let right = min(maxX, area.maxX)
            guard right - left >= minWindowSize.width * 0.4 else { return nil }
            return Ledge(y: y, minX: left, maxX: right, kind: .windowTop)
        }
    }

    /// Боковые грани окна, по которым имеет смысл лезть.
    ///
    /// Годится только та грань, что доходит до собственного верха окна и
    /// упирается в реально видимый кусок его верхней грани. Иначе получались
    /// «лестницы в никуда»: перекрывающее окно рвёт боковую грань пополам, и
    /// у нижнего куска верх — это нижняя кромка чужого окна, где стоять негде.
    func climbableWalls(of rect: CGRect,
                                inFront: ArraySlice<CGRect>,
                                leadingTo tops: [Ledge],
                                visibleAreas: [CGRect]) -> [Wall] {
        guard !tops.isEmpty else { return [] }
        var result: [Wall] = []

        for side in [HorizontalSide.left, .right] {
            let edgeX = side == .left ? rect.minX : rect.maxX
            guard tops.contains(where: { $0.contains(x: edgeX, tolerance: 2) }) else { continue }
            // Грань, прижатая к боку экрана, зрительно не существует: питомец
            // лез бы вверх по пустому краю дисплея.
            guard !visibleAreas.contains(where: { ScreenEnvironment.isFlushWithSide(edgeX, of: $0) }) else { continue }

            let occluders = inFront.filter { $0.minX < edgeX && $0.maxX > edgeX }
            let segments = ScreenEnvironment.subtract(occluders.map { ($0.minY, $0.maxY) },
                                                      from: (rect.minY, rect.maxY))
            // Только верхний кусок: он один заканчивается верхом самого окна.
            guard let top = segments.last, top.1 >= rect.maxY - 1, top.1 - top.0 >= minWallHeight else { continue }
            result.append(Wall(x: edgeX, minY: top.0, maxY: top.1, side: side))
        }
        return result
    }

    // MARK: - Диагностика

    /// Построчный отчёт: какие окна система отдала, что из них отобрано и
    /// какая получилась геометрия. Нужен, чтобы отличать настоящие полки от
    /// призрачных, не гадая по поведению питомца.
    public func diagnosticReport() -> [String] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        let windows = (info as? [[String: Any]]) ?? []
        let geometry = screenGeometry
        let flipY = geometry.primaryMaxY

        var lines = ["экраны: \(NSScreen.screens.count), начало координат по высоте \(Int(flipY))"]
        for area in geometry.visibleAreas {
            lines.append("  видимая область: x \(Int(area.minX))…\(Int(area.maxX)), y \(Int(area.minY))…\(Int(area.maxY))")
        }
        var accepted = 0

        for window in windows {
            switch ScreenEnvironment.classify(window, ownPID: ownPID, primaryMaxY: flipY,
                                              minSize: minWindowSize, screenBounds: geometry.fullBounds,
                                              visibleAreas: geometry.visibleAreas) {
            case .accepted(let scanned):
                accepted += 1
                let r = scanned.rect
                let mark = scanned.isBackdrop ? " [фон, полок не даёт]" : ""
                lines.append("  + \(scanned.owner): x \(Int(r.minX))…\(Int(r.maxX)), верх \(Int(r.maxY)), низ \(Int(r.minY))\(mark)")
            case .rejected(let owner, let reason):
                lines.append("  - \(owner): \(reason)")
            }
        }

        lines.append("отобрано окон: \(accepted)")
        for ledge in ledges {
            lines.append("  полка \(ledge.kind) y=\(Int(ledge.y)) x \(Int(ledge.minX))…\(Int(ledge.maxX))")
        }
        for wall in walls {
            lines.append("  грань \(wall.side) x=\(Int(wall.x)) y \(Int(wall.minY))…\(Int(wall.maxY))")
        }
        return lines
    }

    /// CoreGraphics отдаёт координаты от левого верхнего угла главного экрана,
    /// AppKit считает от левого нижнего. Переводим.
    static func convertToAppKit(_ rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryMaxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Вычитание перекрывающих интервалов из отрезка — так из верхней грани окна
    /// остаются только реально видимые куски.
    static func subtract(_ cutouts: [(CGFloat, CGFloat)], from segment: (CGFloat, CGFloat)) -> [(CGFloat, CGFloat)] {
        var pieces = [segment]
        for cut in cutouts.sorted(by: { $0.0 < $1.0 }) {
            var next: [(CGFloat, CGFloat)] = []
            for piece in pieces {
                if cut.1 <= piece.0 || cut.0 >= piece.1 { next.append(piece); continue }
                if cut.0 > piece.0 { next.append((piece.0, cut.0)) }
                if cut.1 < piece.1 { next.append((cut.1, piece.1)) }
            }
            pieces = next
        }
        return pieces
    }
}
