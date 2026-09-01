import Foundation
import QuartzCore

/// Тикер игрового цикла. 30 кадров/с достаточно для питомца и заметно
/// экономнее по батарее, чем 60.
public final class GameLoop {

    public var targetFPS: Double = 30 {
        didSet {
            guard targetFPS != oldValue, timer != nil else { return }
            start()
        }
    }

    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private let onTick: (TimeInterval) -> Void

    public init(onTick: @escaping (TimeInterval) -> Void) {
        self.onTick = onTick
    }

    public var isRunning: Bool { timer != nil }

    public func start() {
        stop()
        lastTick = CACurrentMediaTime()
        let interval = 1.0 / targetFPS
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Без .common анимация замирает во время трекинга меню и ресайза окон.
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        // Ограничиваем dt: после сна системы или залипания рантайма скачок
        // в несколько секунд протащил бы питомца сквозь все полки.
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        onTick(dt)
    }
}
