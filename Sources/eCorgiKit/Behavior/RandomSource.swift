import Foundation

/// Источник случайности. Отдельный тип нужен, чтобы в тестах автомат
/// поведений можно было прогонять детерминированно.
public struct RandomSource {

    private let next: () -> Double

    public init(_ next: @escaping () -> Double) { self.next = next }

    public static var system: RandomSource {
        RandomSource { Double.random(in: 0..<1) }
    }

    /// Заранее заданная последовательность, зацикленная по кругу — для тестов.
    public static func fixed(_ values: [Double]) -> RandomSource {
        var index = 0
        return RandomSource {
            defer { index += 1 }
            return values.isEmpty ? 0 : values[index % values.count]
        }
    }

    /// Значение в [0, 1).
    public func unit() -> Double {
        min(max(next(), 0), 0.999_999_9)
    }

    public func value(in range: ClosedRange<Double>) -> Double {
        guard range.upperBound > range.lowerBound else { return range.lowerBound }
        return range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    public func value(in range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat(value(in: Double(range.lowerBound)...Double(range.upperBound)))
    }

    /// `true` с заданной вероятностью.
    public func chance(_ probability: Double) -> Bool {
        unit() < probability
    }
}
