import CoreGraphics

/// «Полка», по которой питомец может ходить: низ экрана или верхний край чужого окна.
/// Координаты — в системе AppKit (начало в левом нижнем углу главного экрана, Y вверх).
public struct Ledge: Equatable {

    public enum Kind: Equatable {
        case ground     // нижний край экрана
        case windowTop  // верхняя грань окна другого приложения
    }

    public var y: CGFloat
    public var minX: CGFloat
    public var maxX: CGFloat
    public var kind: Kind

    public init(y: CGFloat, minX: CGFloat, maxX: CGFloat, kind: Kind) {
        self.y = y
        self.minX = minX
        self.maxX = maxX
        self.kind = kind
    }

    public var width: CGFloat { maxX - minX }

    public func contains(x: CGFloat, tolerance: CGFloat = 0) -> Bool {
        x >= minX - tolerance && x <= maxX + tolerance
    }

    /// Ближайшая точка полки по X — нужна, чтобы «подтянуть» питомца при приземлении.
    public func clampX(_ x: CGFloat) -> CGFloat {
        min(max(x, minX), maxX)
    }
}

/// Сторона грани относительно окна. Нужна и стенам, и точке подвеса:
/// от неё зависит, с какой стороны висит тело питомца и куда он смотрит.
public enum HorizontalSide: Equatable, Sendable {
    case left   // левая грань окна
    case right  // правая грань окна

    /// Куда смотрит питомец, держась за эту грань — «лицом к окну».
    public var facing: CGFloat { self == .left ? 1 : -1 }
    /// В какую сторону от грани оказывается тело питомца.
    public var outward: CGFloat { self == .left ? -1 : 1 }
}

/// Вертикальная грань окна, по которой питомец может залезть наверх.
public struct Wall: Equatable {

    public var x: CGFloat
    public var minY: CGFloat
    public var maxY: CGFloat
    public var side: HorizontalSide

    public init(x: CGFloat, minY: CGFloat, maxY: CGFloat, side: HorizontalSide) {
        self.x = x
        self.minY = minY
        self.maxY = maxY
        self.side = side
    }

    public var height: CGFloat { maxY - minY }

    public func contains(y: CGFloat, tolerance: CGFloat = 0) -> Bool {
        y >= minY - tolerance && y <= maxY + tolerance
    }
}

/// Точка, за которую питомец держится, свисая с грани окна.
public struct HangAnchor: Equatable {
    /// Место захвата — конец верхней грани окна.
    public var x: CGFloat
    public var y: CGFloat
    public var side: HorizontalSide

    public init(x: CGFloat, y: CGFloat, side: HorizontalSide) {
        self.x = x
        self.y = y
        self.side = side
    }
}
