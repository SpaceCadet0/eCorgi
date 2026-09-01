import AppKit

/// Вью питомца. Кадр показывается через `contents` слоя, а не через `draw(_:)`:
/// смена кадра тогда стоит одну запись в свойство, а композицию делает
/// оконный сервер. Спрайт кладётся низом-по-центру, чтобы «лапы» всегда
/// совпадали с позицией питомца независимо от размера кадра.
final class PetView: NSView {

    private let spriteLayer = CALayer()

    private(set) var frame_: SpriteFrame?
    private(set) var mirrored: Bool = false
    /// Наклон в радианах: питомец качается, вися на грани окна.
    private(set) var sway: CGFloat = 0

    var scale: CGFloat = 1 { didSet { if scale != oldValue { layoutSprite() } } }

    /// Обработчики мыши задаёт контроллер окна.
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(spriteLayer)
        spriteLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
        spriteLayer.magnificationFilter = .linear
        spriteLayer.minificationFilter = .trilinear
        // Неявные CoreAnimation-анимации превратили бы смену кадра в плавный
        // кроссфейд, а нам нужна честная покадровка.
        spriteLayer.actions = ["contents": NSNull(), "position": NSNull(),
                               "bounds": NSNull(), "transform": NSNull()]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    func display(frame: SpriteFrame, mirrored: Bool, sway: CGFloat = 0) {
        let frameChanged = frame !== frame_
        let mirrorChanged = mirrored != self.mirrored
        // Угол сравниваем с допуском: перекладывать transform ради сотой
        // доли градуса незачем.
        let swayChanged = abs(sway - self.sway) > 0.002
        guard frameChanged || mirrorChanged || swayChanged else { return }

        frame_ = frame
        self.mirrored = mirrored
        self.sway = sway

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if frameChanged { spriteLayer.contents = frame.image }
        layoutSprite()
        CATransaction.commit()
    }

    private func layoutSprite() {
        guard let frame_ else { return }
        let size = CGSize(width: frame_.size.width * scale, height: frame_.size.height * scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.bounds = CGRect(origin: .zero, size: size)
        spriteLayer.position = CGPoint(x: bounds.width / 2, y: spriteBottomInset)
        spriteLayer.transform = spriteTransform(height: size.height)
        CATransaction.commit()
    }

    /// Отражение по горизонтали (вместо отдельных кадров «влево») плюс
    /// покачивание. Точка вращения — верхняя кромка спрайта: именно ей
    /// питомец держится за грань окна.
    private func spriteTransform(height: CGFloat) -> CATransform3D {
        var transform = mirrored ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
        guard sway != 0 else { return transform }
        // anchorPoint слоя — низ-центр, поэтому сдвигаем систему координат
        // к верху спрайта, поворачиваем и возвращаем обратно.
        transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(0, -height, 0))
        transform = CATransform3DConcat(transform, CATransform3DMakeRotation(sway, 0, 0, 1))
        return CATransform3DConcat(transform, CATransform3DMakeTranslation(0, height, 0))
    }

    override func layout() {
        super.layout()
        layoutSprite()
    }

    /// Отступ спрайта от низа окна. Наклон при покачивании выносит лапы
    /// за габариты кадра, поэтому вокруг спрайта нужен запас.
    var spriteBottomInset: CGFloat = 0 {
        didSet { if spriteBottomInset != oldValue { layoutSprite() } }
    }

    /// Прямоугольник кадра внутри вью.
    var spriteRect: CGRect {
        guard let frame_ else { return .zero }
        let size = CGSize(width: frame_.size.width * scale, height: frame_.size.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: spriteBottomInset,
                      width: size.width, height: size.height)
    }

    /// Попал ли курсор в непрозрачный пиксель спрайта. Используется и для
    /// hit-теста, и для динамического переключения `ignoresMouseEvents` у окна.
    func isOpaquePixel(atViewPoint point: CGPoint) -> Bool {
        let rect = spriteRect
        guard rect.contains(point), let frame_ else { return false }

        var unit = CGPoint(x: (point.x - rect.minX) / rect.width,
                           y: (point.y - rect.minY) / rect.height)
        if mirrored { unit.x = 1 - unit.x }
        return frame_.isOpaque(atUnit: unit)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return isOpaquePixel(atViewPoint: local) ? self : nil
    }

    // MARK: - Мышь

    override func mouseDown(with event: NSEvent) { onMouseDown?(NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(NSEvent.mouseLocation) }
}
