import AppKit
import CoreImage

// Переэкспорт отдельных действий из исходных кадров в масштаб пака.
//
// Кадры действий приходят из разных источников, и персонаж на них выходит
// разного размера. Пересчитывать уже уменьшенные кадры пака значит
// пересэмплировать их второй раз; вместо этого действие пересобирается из
// исходника за один проход — сразу в нужный масштаб и на холст пака.

let sourceDir = URL(fileURLWithPath: CommandLine.arguments[1])
let packDir = URL(fileURLWithPath: CommandLine.arguments[2])
let dryRun = CommandLine.arguments.contains("--dry-run")

var factors: [String: CGFloat] = [:]
for pair in CommandLine.arguments[3].split(separator: ",") {
    let kv = pair.split(separator: "=")
    guard kv.count == 2, let v = Double(kv[1]) else { continue }
    factors[String(kv[0])] = CGFloat(v)
}
guard !factors.isEmpty else { print("не заданы действия и коэффициенты"); exit(1) }

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

func scaled(_ image: CGImage, by factor: CGFloat) -> CGImage {
    let tw = max(1, Int((CGFloat(image.width) * factor).rounded()))
    let th = max(1, Int((CGFloat(image.height) * factor).rounded()))
    let filter = CIFilter(name: "CILanczosScaleTransform")!
    filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
    filter.setValue(Double(factor), forKey: kCIInputScaleKey)
    filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
    return ciContext.createCGImage(filter.outputImage!,
                                   from: CGRect(x: 0, y: 0, width: tw, height: th))!
}

/// Холст пака — берём у любого его кадра.
guard let sample = (try! FileManager.default.contentsOfDirectory(at: packDir, includingPropertiesForKeys: nil))
        .first(where: { $0.pathExtension == "png" }),
      let sampleImage = NSImage(contentsOf: sample)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("не удалось прочитать холст пака"); exit(1)
}
let canvas = (w: sampleImage.width, h: sampleImage.height)
print("холст пака: \(canvas.w)x\(canvas.h)")

struct Ready { let name: String, action: String; let image: CGImage; let x: Int, y: Int; let height: Int }
var ready: [Ready] = []
var overflow: [String] = []

for (action, factor) in factors.sorted(by: { $0.key < $1.key }) {
    let sources = (try! FileManager.default.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil))
        .filter { $0.pathExtension == "png" && $0.deletingPathExtension().lastPathComponent.hasPrefix(action + "_") }
        .filter { Int($0.deletingPathExtension().lastPathComponent.dropFirst(action.count + 1)) != nil }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !sources.isEmpty else { print("  \(action): исходников не найдено"); continue }

    var heights: [Int] = []
    for url in sources {
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let source = contentBounds(image) else { continue }
        let small = scaled(image, by: factor)
        guard let content = contentBounds(small) else { continue }

        // Отступ от земли и смещение от центра переносятся, только делятся.
        let bottom = Int((source.origin.y * factor).rounded())
        let offset = Int(((source.midX - CGFloat(image.width) / 2) * factor).rounded())
        let x = Int((CGFloat(canvas.w) / 2 + CGFloat(offset) - content.midX).rounded())
        let y = Int((CGFloat(bottom) - content.origin.y).rounded())

        if x + Int(content.minX) < 0 || x + Int(content.maxX) >= canvas.w
            || y + Int(content.minY) < 0 || y + Int(content.maxY) >= canvas.h {
            overflow.append(url.deletingPathExtension().lastPathComponent)
        }
        heights.append(Int(content.height))
        ready.append(Ready(name: url.lastPathComponent, action: action, image: small, x: x, y: y,
                           height: Int(content.height)))
    }
    print(String(format: "  %-8@ x%.3f  кадров %d, рост %d–%d",
                 action as NSString, Double(factor), heights.count, heights.min() ?? 0, heights.max() ?? 0))
}

guard overflow.isEmpty else {
    print("не помещается на холст: \(overflow.joined(separator: ", "))")
    print("правка отменена")
    exit(1)
}
guard !dryRun else { print("(пробный прогон, файлы не тронуты)"); exit(0) }

backUpFrames(from: packDir)

for item in ready {
    let ctx = CGContext(data: nil, width: canvas.w, height: canvas.h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: canvas.w, height: canvas.h))
    // Целочисленный сдвиг: пересэмплирование было ровно одно, при уменьшении.
    ctx.interpolationQuality = .none
    ctx.draw(item.image, in: CGRect(x: item.x, y: item.y,
                                    width: item.image.width, height: item.image.height))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: canvas.w, height: canvas.h)
    try! rep.representation(using: .png, properties: [:])!
        .write(to: packDir.appendingPathComponent(item.name))
}
print("готово, кадров: \(ready.count)")

/// Резервная копия папки перед изменением кадров.
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
