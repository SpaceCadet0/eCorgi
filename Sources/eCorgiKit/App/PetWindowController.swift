import AppKit

/// Прозрачное безрамочное окно, которое ездит за питомцем.
/// Окно размером с самый большой кадр атласа: так спрайт не «дрожит»
/// при смене кадров разного размера, а система не переклеивает окно каждый тик.
public final class PetWindowController {

    private let panel: NSPanel
    private let view: PetView
    private let pet: Pet
    private let settings: SettingsStore

    /// Держим окно кликабельным всё время перетаскивания, даже если
    /// курсор ушёл со спрайта.
    private var isDragging = false
    /// Смещение точки захвата относительно лап — чтобы питомец не прыгал под курсор.
    private var dragGrabOffset: CGSize = .zero

    public init(pet: Pet, atlas: SpriteAtlas, settings: SettingsStore = .shared) {
        self.pet = pet
        self.settings = settings

        let size = PetWindowController.windowSize(for: atlas, scale: CGFloat(settings.scale))

        panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Панель не должна перехватывать фокус у активного приложения.
        panel.becomesKeyOnlyIfNeeded = true

        view = PetView(frame: CGRect(origin: .zero, size: size))
        view.scale = CGFloat(settings.scale)
        view.spriteBottomInset = PetWindowController.padding.height
        panel.contentView = view

        view.onMouseDown = { [weak self] location in self?.beginDrag(at: location) }
        view.onMouseDragged = { [weak self] location in self?.continueDrag(at: location) }
        view.onMouseUp = { [weak self] _ in self?.endDrag() }

        panel.orderFrontRegardless()
        sync()
    }

    /// Запас вокруг спрайта: при покачивании на грани окна наклонённые лапы
    /// выходят за габариты кадра, а окно обрезает всё лишнее.
    static let padding = CGSize(width: 28, height: 14)

    static func windowSize(for atlas: SpriteAtlas, scale: CGFloat) -> CGSize {
        CGSize(width: atlas.maxFrameSize.width * scale + padding.width * 2,
               height: atlas.maxFrameSize.height * scale + padding.height * 2)
    }

    public func setScale(_ scale: CGFloat, atlas: SpriteAtlas) {
        view.scale = scale
        panel.setContentSize(PetWindowController.windowSize(for: atlas, scale: scale))
        view.frame = CGRect(origin: .zero, size: panel.frame.size)
        sync()
    }

    /// Вызывается на каждом тике игрового цикла.
    public func sync() {
        view.display(frame: pet.animator.currentFrame, mirrored: pet.facing < 0, sway: pet.sway)

        // Округляем до целых точек: перемещение окна на доли пикселя
        // ничего не даёт визуально, но каждый раз дёргает оконный сервер.
        let size = panel.frame.size
        let origin = CGPoint(x: (pet.position.x - size.width / 2).rounded(),
                             y: (pet.position.y - PetWindowController.padding.height).rounded())
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
        updateMousePassthrough()
    }

    /// Окно ловит мышь только когда курсор реально над корги — в остальное
    /// время клики должны уходить в приложения под ним.
    private func updateMousePassthrough() {
        if isDragging {
            setPassthrough(false)
            return
        }
        let frame = panel.frame
        let mouse = NSEvent.mouseLocation
        // Дешёвая проверка по рамке окна: пиксельный тест нужен, только
        // когда курсор вообще над окном питомца.
        guard frame.contains(mouse) else {
            setPassthrough(true)
            return
        }
        let local = CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY)
        setPassthrough(!view.isOpaquePixel(atViewPoint: local))
    }

    private func setPassthrough(_ ignore: Bool) {
        guard panel.ignoresMouseEvents != ignore else { return }
        panel.ignoresMouseEvents = ignore
    }

    // MARK: - Перетаскивание

    private func beginDrag(at location: CGPoint) {
        isDragging = true
        dragGrabOffset = CGSize(width: location.x - pet.position.x, height: location.y - pet.position.y)
        pet.dragTarget = pet.position
        pet.isDragged = true
    }

    private func continueDrag(at location: CGPoint) {
        guard isDragging else { return }
        pet.dragTarget = CGPoint(x: location.x - dragGrabOffset.width,
                                 y: location.y - dragGrabOffset.height)
    }

    private func endDrag() {
        isDragging = false
        pet.isDragged = false
    }

    public func close() {
        panel.orderOut(nil)
    }
}
