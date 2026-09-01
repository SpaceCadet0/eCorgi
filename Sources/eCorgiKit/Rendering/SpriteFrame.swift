import AppKit

/// Один кадр анимации, подготовленный к отрисовке.
///
/// Держим именно `CGImage`: его можно положить прямо в `contents` слоя,
/// и тогда каждый кадр обходится без перерисовки — картинку компонует
/// оконный сервер. `NSImage.draw(in:)` на каждом тике заметно дороже.
public final class SpriteFrame {

    public let image: CGImage
    /// Размер в точках (для @2x-ассетов он вдвое меньше пиксельного).
    public let size: CGSize

    /// Маска непрозрачности строится лениво — она нужна только для
    /// попадания курсора, то есть в редкие моменты.
    private var alphaMask: AlphaMask?

    public init(image: CGImage, size: CGSize) {
        self.image = image
        self.size = size
    }

    public convenience init?(nsImage: NSImage) {
        var rect = CGRect(origin: .zero, size: nsImage.size)
        guard let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        self.init(image: cgImage, size: nsImage.size)
    }

    /// Прямоугольник непрозрачных пикселей в точках, в системе кадра:
    /// начало координат — левый нижний угол холста.
    ///
    /// Движку нужен именно персонаж, а не холст: после приведения кадров к
    /// общему размеру над мелкими рисунками остаётся много пустоты, и мерить
    /// питомца по холсту значит промахиваться на сотню пунктов.
    public var contentBounds: CGRect {
        if alphaMask == nil { alphaMask = AlphaMask(image: image) }
        guard let mask = alphaMask else { return CGRect(origin: .zero, size: size) }
        return mask.contentBounds(scaledTo: size)
    }

    /// Непрозрачен ли пиксель в нормированных координатах (0…1, начало слева снизу).
    public func isOpaque(atUnit point: CGPoint) -> Bool {
        guard point.x >= 0, point.x <= 1, point.y >= 0, point.y <= 1 else { return false }
        if alphaMask == nil { alphaMask = AlphaMask(image: image) }
        return alphaMask?.isOpaque(atUnit: point) ?? true
    }
}

/// Одноканальная карта альфы кадра — по байту на пиксель.
final class AlphaMask {

    private let width: Int
    private let height: Int
    private let data: [UInt8]
    /// Границы непрозрачных пикселей в координатах маски.
    private let opaque: (minX: Int, minY: Int, maxX: Int, maxY: Int)?

    init?(image: CGImage) {
        // Уменьшаем маску: для попадания мышью хватает грубого разрешения,
        // зато памяти на весь спрайт-пак уходит немного.
        let scale = max(1, max(image.width, image.height) / 128)
        let w = max(1, image.width / scale)
        let h = max(1, image.height / scale)

        var buffer = [UInt8](repeating: 0, count: w * h)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base,
                                          width: w,
                                          height: h,
                                          bitsPerComponent: 8,
                                          bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        width = w
        height = h
        data = buffer

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where buffer[y * w + x] > 38 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        opaque = maxX < 0 ? nil : (minX, minY, maxX, maxY)
    }

    /// Границы содержимого, пересчитанные в размер кадра.
    /// Строки маски идут сверху вниз, а результат нужен в системе AppKit —
    /// с началом в левом нижнем углу, поэтому вертикаль переворачивается.
    func contentBounds(scaledTo size: CGSize) -> CGRect {
        guard let opaque, width > 0, height > 0 else { return CGRect(origin: .zero, size: size) }
        let sx = size.width / CGFloat(width), sy = size.height / CGFloat(height)
        return CGRect(x: CGFloat(opaque.minX) * sx,
                      y: CGFloat(height - 1 - opaque.maxY) * sy,
                      width: CGFloat(opaque.maxX - opaque.minX + 1) * sx,
                      height: CGFloat(opaque.maxY - opaque.minY + 1) * sy)
    }

    /// Начало координат в нормированной системе — слева снизу, как в AppKit.
    func isOpaque(atUnit point: CGPoint, threshold: UInt8 = 38) -> Bool {
        let x = min(width - 1, max(0, Int(point.x * CGFloat(width))))
        // Строка 0 буфера CGContext — это верх кадра, а point.y отсчитывается
        // от низа: без переворота маска попадания оказывалась зеркальной.
        let row = min(height - 1, max(0, Int((1 - point.y) * CGFloat(height))))
        return data[row * width + x] > threshold
    }
}
