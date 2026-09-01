import AppKit

/// Положение курсора и его скорость. Опрашиваем на каждом тике вместо
/// глобального монитора событий — дешевле и не требует спец. разрешений.
public final class CursorTracker {

    public private(set) var location: CGPoint = .zero
    public private(set) var velocity: CGVector = .zero

    public init() {
        location = NSEvent.mouseLocation
    }

    public func update(_ dt: TimeInterval) {
        let current = NSEvent.mouseLocation
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
