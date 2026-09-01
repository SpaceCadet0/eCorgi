import AppKit

/// Положение курсора и его скорость. Опрашиваем на каждом тике вместо
/// глобального монитора событий — дешевле и не требует спец. разрешений.
public final class CursorTracker {

    public private(set) var location: CGPoint = .zero
    public private(set) var velocity: CGVector = .zero

    /// Откуда берётся положение курсора. Подменяется в тестах: иначе проверить
    /// реакцию на мышь нельзя — трекер читал бы настоящий курсор машины.
    private let source: () -> CGPoint

    public init(source: @escaping () -> CGPoint = { NSEvent.mouseLocation }) {
        self.source = source
        location = source()
    }

    public func update(_ dt: TimeInterval) {
        let current = source()
        guard dt > 0 else { location = current; return }
        velocity = CGVector(dx: (current.x - location.x) / dt, dy: (current.y - location.y) / dt)
        location = current
    }

    public var speed: CGFloat {
        (velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot()
    }

    public func distance(to point: CGPoint) -> CGFloat {
        hypot(location.x - point.x, location.y - point.y)
    }
}
