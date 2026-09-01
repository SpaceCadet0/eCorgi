import CoreGraphics

/// Гравитация и поиск опоры. Чистые функции — их удобно покрывать тестами.
public enum PhysicsHelper {

    /// Ускорение свободного падения, пунктов/с².
    public static let gravity: CGFloat = 2000
    /// Ограничение скорости падения, чтобы питомец не «телепортировался» сквозь полки.
    public static let maxFallSpeed: CGFloat = 1800
    /// Допуск по вертикали, при котором питомец считается стоящим на полке.
    public static let groundTolerance: CGFloat = 2.5

    /// Полка прямо под лапами (или ровно под ними в пределах допуска).
    public static func support(at point: CGPoint, in ledges: [Ledge], tolerance: CGFloat = groundTolerance) -> Ledge? {
        ledges
            .filter { abs($0.y - point.y) <= tolerance && $0.contains(x: point.x) }
            .max { $0.y < $1.y }
    }

    /// Полка, которую питомец пересёк за кадр, двигаясь сверху вниз.
    /// Возвращает самую высокую из пересечённых — на неё он и приземлится.
    public static func landing(from oldY: CGFloat, to newY: CGFloat, x: CGFloat, in ledges: [Ledge]) -> Ledge? {
        guard newY < oldY else { return nil }
        return ledges
            .filter { $0.contains(x: x) && $0.y <= oldY + groundTolerance && $0.y >= newY }
            .max { $0.y < $1.y }
    }

    /// Шаг падения: новая позиция и вертикальная скорость.
    public static func applyGravity(position: CGPoint, velocityY: CGFloat, dt: CGFloat) -> (position: CGPoint, velocityY: CGFloat) {
        let newVelocity = max(velocityY - gravity * dt, -maxFallSpeed)
        let newPosition = CGPoint(x: position.x, y: position.y + newVelocity * dt)
        return (newPosition, newVelocity)
    }

    /// Один шаг свободного полёта: гравитация, снос по горизонтали и проверка
    /// приземления. Общий для падения, прыжка на месте и спрыгивания —
    /// траектория у всех троих одна и та же, различается только старт.
    ///
    /// Если полка найдена, возвращённая позиция уже «притянута» к ней,
    /// а скорость обнулена.
    public static func advanceThroughAir(position: CGPoint,
                                         velocity: CGVector,
                                         dt: CGFloat,
                                         airDrag: CGFloat = 0,
                                         in ledges: [Ledge]) -> (position: CGPoint, velocity: CGVector, landing: Ledge?) {
        var newVelocity = velocity
        newVelocity.dy = max(velocity.dy - gravity * dt, -maxFallSpeed)
        newVelocity.dx *= (1 - airDrag * dt)

        var newPosition = CGPoint(x: position.x + newVelocity.dx * dt,
                                  y: position.y + newVelocity.dy * dt)

        guard let ledge = landing(from: position.y, to: newPosition.y, x: newPosition.x, in: ledges) else {
            return (newPosition, newVelocity, nil)
        }
        newPosition = CGPoint(x: ledge.clampX(newPosition.x), y: ledge.y)
        return (newPosition, .zero, ledge)
    }
}
