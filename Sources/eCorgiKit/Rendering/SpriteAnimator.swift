import AppKit

/// Покадровая анимация: держит текущее действие, индекс кадра и таймер кадра.
public final class SpriteAnimator {

    private let atlas: SpriteAtlas
    private var currentFrames: [SpriteFrame]
    private var elapsedInFrame: TimeInterval = 0

    public private(set) var action: SpriteAction
    public private(set) var frameIndex: Int = 0
    /// Прошла ли неповторяющаяся анимация до последнего кадра.
    public private(set) var isFinished: Bool = false

    /// Кадров в секунду для текущего действия.
    public var fps: Double = 12
    /// Зациклена ли анимация. Для `fall`, `land`, `jump` — обычно `false`.
    public var loops: Bool = true

    /// Сколько последних кадров зацикливать после первого прохода.
    ///
    /// Ноль — обычное поведение: либо весь цикл по кругу, либо остановка на
    /// последнем кадре. Значение больше единицы даёт «вступление и петля»:
    /// анимация один раз проходит целиком, а дальше по кругу идут только
    /// последние `tail` кадров. Так сделано перетаскивание — питомец
    /// один раз дёргается всем телом, а потом только болтает лапами.
    public var tail: Int = 0

    public init(atlas: SpriteAtlas, action: SpriteAction = .idle) {
        self.atlas = atlas
        self.action = action
        self.currentFrames = atlas.frames(for: action)
    }

    public var frameCount: Int { currentFrames.count }

    public var currentFrame: SpriteFrame {
        currentFrames[min(frameIndex, currentFrames.count - 1)]
    }

    /// Переключение действия. Повторный вызов с тем же действием ничего не сбрасывает,
    /// поэтому состояния могут звать его каждый кадр без вреда.
    public func play(_ action: SpriteAction, fps: Double = 12, loops: Bool = true, tail: Int = 0) {
        self.fps = fps
        self.loops = loops
        self.tail = tail
        guard action != self.action else { return }
        self.action = action
        self.currentFrames = atlas.frames(for: action)
        self.frameIndex = 0
        self.elapsedInFrame = 0
        self.isFinished = false
    }

    /// Индекс, с которого начинается хвостовая петля.
    /// Равен нулю, если хвост не задан — тогда петля охватывает всю анимацию.
    public var tailStart: Int {
        tail > 1 ? max(0, currentFrames.count - min(tail, currentFrames.count)) : 0
    }

    /// Подобрать темп так, чтобы весь цикл уложился в заданное время.
    ///
    /// Нужно там, где длительность действия задана физикой, а не таблицей:
    /// полёт в прыжке короче, чем анимация при обычном темпе, и без подгонки
    /// половина кадров просто не успевает показаться.
    ///
    /// Возвращает требуемую частоту — состояние держит её у себя, потому что
    /// `play` на каждом тике иначе вернул бы прежнее значение.
    @discardableResult
    public func fitCycle(into seconds: TimeInterval) -> Double {
        guard seconds > 0, frameCount > 1 else { return fps }
        fps = Double(frameCount) / seconds
        return fps
    }

    /// Принудительно начать анимацию заново (например, повторный лай).
    public func restart() {
        frameIndex = 0
        elapsedInFrame = 0
        isFinished = false
    }

    public func update(_ dt: TimeInterval) {
        guard currentFrames.count > 1, fps > 0 else { return }
        let frameDuration = 1.0 / fps
        elapsedInFrame += dt

        while elapsedInFrame >= frameDuration {
            elapsedInFrame -= frameDuration
            if frameIndex + 1 < currentFrames.count {
                frameIndex += 1
            } else if tail > 1 {
                // Дошли до конца — возвращаемся не в начало, а на хвост.
                // Хвост длиннее самой анимации означает обычный цикл.
                frameIndex = max(0, currentFrames.count - min(tail, currentFrames.count))
            } else if loops {
                frameIndex = 0
            } else {
                isFinished = true
                elapsedInFrame = 0
                break
            }
        }
    }
}
