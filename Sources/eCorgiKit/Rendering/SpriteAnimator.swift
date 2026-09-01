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
    public func play(_ action: SpriteAction, fps: Double = 12, loops: Bool = true) {
        self.fps = fps
        self.loops = loops
        guard action != self.action else { return }
        self.action = action
        self.currentFrames = atlas.frames(for: action)
        self.frameIndex = 0
        self.elapsedInFrame = 0
        self.isFinished = false
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
