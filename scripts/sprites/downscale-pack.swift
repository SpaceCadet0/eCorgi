import AppKit
import CoreImage

// Уменьшение пака в целое число раз с приведением к общему холсту.
//
// Два решения ради резкости:
//
// 1. Ланцош вместо обычной отрисовки. На кадрах корги он даёт примерно на
//    6% больше энергии градиента, чем усреднение 3x3, и меньше выбросов,
//    чем рисование Quartz с высоким качеством.
//
// 2. Готовый уменьшенный кадр переносится на общий холст целочисленным
//    сдвигом. Пересэмплирование происходит ровно один раз. Именно нецелое
//    смещение при переносе размыло пак в прошлый раз: холст шириной 89 и
//    кадр шириной 70 давали сдвиг на полпикселя.

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let divisor = CommandLine.arguments.count > 2 ? (Int(CommandLine.arguments[2]) ?? 3) : 3
let dryRun = CommandLine.arguments.contains("--dry-run")
guard divisor >= 1 else { print("делитель должен быть не меньше единицы"); exit(1) }

func pixels(_ image: CGImage) -> (w: Int, h: Int, d: [UInt8]) {
    let w = image.width, h = image.height
    var d = [UInt8](repeating: 0, count: w * h * 4)
    d.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
            .draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (w, h, d)
}

/// Границы непрозрачного содержимого; начало координат — левый нижний угол.
func contentBounds(_ image: CGImage) -> CGRect? {
    let p = pixels(image)
    var minX = p.w, maxX = -1, minRow = p.h, maxRow = -1
    for y in 0..<p.h {
        for x in 0..<p.w where p.d[(y * p.w + x) * 4 + 3] > 38 {
            minX = min(minX, x); maxX = max(maxX, x)
            minRow = min(minRow, y); maxRow = max(maxRow, y)
        }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: CGFloat(minX), y: CGFloat(p.h - 1 - maxRow),
                  width: CGFloat(maxX - minX + 1), height: CGFloat(maxRow - minRow + 1))
}

let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

func downscaled(_ image: CGImage) -> CGImage {
    let tw = max(1, image.width / divisor), th = max(1, image.height / divisor)
    guard divisor > 1 else { return image }
    let filter = CIFilter(name: "CILanczosScaleTransform")!
    filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
    filter.setValue(1.0 / Double(divisor), forKey: kCIInputScaleKey)
    filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
    return ciContext.createCGImage(filter.outputImage!,
                                   from: CGRect(x: 0, y: 0, width: tw, height: th))!
}

struct Frame {
    let url: URL, action: String
    let small: CGImage          // уже уменьшенный кадр
    let content: CGRect         // его содержимое
    let bottom: Int, offset: Int  // куда его поставить на общем холсте
}

var frames: [Frame] = []
for url in (try! FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
    .filter({ $0.pathExtension.lowercased() == "png" })
    .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    let name = url.deletingPathExtension().lastPathComponent
    guard let sep = name.lastIndex(of: "_"), Int(name[name.index(after: sep)...]) != nil,
          let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let source = contentBounds(image) else { continue }

    let small = downscaled(image)
    guard let content = contentBounds(small) else { continue }
    // Отступ от земли и смещение от центра сохраняются, только делятся.
    let bottom = Int((source.origin.y / CGFloat(divisor)).rounded())
    let sourceCentre = source.midX - CGFloat(image.width) / 2
    let offset = Int((sourceCentre / CGFloat(divisor)).rounded())
    frames.append(Frame(url: url, action: String(name[name.startIndex..<sep]),
                        small: small, content: content, bottom: bottom, offset: offset))
}
guard !frames.isEmpty else { print("кадров не найдено"); exit(1) }

// Общий холст — по самому крупному содержимому после уменьшения.
var halfWidth = 0, top = 0
for f in frames {
    let half = Int((f.content.width / 2).rounded(.up))
    halfWidth = max(halfWidth, abs(f.offset) + half)
    top = max(top, f.bottom + Int(f.content.height))
}
let margin = 4
let canvas = (w: (halfWidth + margin) * 2, h: top + margin)

let firstCanvas = NSImage(contentsOf: frames[0].url)!
    .cgImage(forProposedRect: nil, context: nil, hints: nil)!
print("делитель: \(divisor), ядро: Ланцош")
print("холст: было \(firstCanvas.width)x\(firstCanvas.height) и ещё разные, стало \(canvas.w)x\(canvas.h)")

var byAction: [String: (lo: Int, hi: Int)] = [:]
for f in frames {
    let h = Int(f.content.height)
    let cur = byAction[f.action] ?? (Int.max, 0)
    byAction[f.action] = (min(cur.lo, h), max(cur.hi, h))
}
print("рост персонажа после уменьшения:")
for (a, v) in byAction.sorted(by: { $0.key < $1.key }) {
    print(String(format: "  %-10@ %d–%d", a as NSString, v.lo, v.hi))
}
guard !dryRun else { print("(пробный прогон, файлы не тронуты)"); exit(0) }

backUpFrames(from: dir)

for f in frames {
    let ctx = CGContext(data: nil, width: canvas.w, height: canvas.h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: canvas.w, height: canvas.h))
    // Целочисленный сдвиг: второго пересэмплирования не происходит.
    ctx.interpolationQuality = .none
    let x = (CGFloat(canvas.w) / 2 + CGFloat(f.offset) - f.content.midX).rounded()
    let y = (CGFloat(f.bottom) - f.content.origin.y).rounded()
    ctx.draw(f.small, in: CGRect(x: x, y: y,
                                 width: CGFloat(f.small.width), height: CGFloat(f.small.height)))

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: canvas.w, height: canvas.h)
    try! rep.representation(using: .png, properties: [:])!.write(to: f.url)
}
print("готово, кадров: \(frames.count)")

/// Резервная копия папки перед изменением кадров.
///
/// Каждая правка растрового кадра необратима: пересэмплирование теряет
/// детали, и вернуть исходник неоткуда, если он ещё не в git. Копия кладётся
/// вне `Resources/` — иначе она уехала бы внутрь собранного приложения.
func backUpFrames(from dir: URL) {
    let root = dir.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let stamp = ISO8601DateFormatter()
    stamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withDashSeparatorInDate]
    let name = stamp.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let to = root.appendingPathComponent("sprite-backups").appendingPathComponent(name)
    do {
        try FileManager.default.createDirectory(at: to.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: dir, to: to)
        print("резервная копия: \(to.path)")
    } catch {
        print("НЕ УДАЛОСЬ сделать резервную копию: \(error.localizedDescription)")
        print("правка отменена")
        exit(1)
    }
}
