import AppKit

// Изменение масштаба кадров по действиям.
//
// Кадры разных действий приходят из разных спрайт-листов, и персонаж на них
// оказывается разного размера — питомец «съёживается», начиная бежать.
// Здесь каждому действию задаётся свой коэффициент, после чего холст
// пересчитывается под новое содержимое.
//
// Уменьшается кадр целиком, а не вырезанный персонаж: так сохраняются и
// отступ от земли, и смещение относительно центра, то есть заданная поза.

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let dryRun = CommandLine.arguments.contains("--dry-run")

var factors: [String: CGFloat] = [:]
for pair in CommandLine.arguments[2].split(separator: ",") {
    let kv = pair.split(separator: "=")
    guard kv.count == 2, let v = Double(kv[1]) else { continue }
    factors[String(kv[0])] = CGFloat(v)
}

struct Frame {
    let url: URL, action: String, image: CGImage
    let canvas: CGSize, content: CGRect   // content: начало в левом нижнем углу
}

func contentBounds(_ image: CGImage) -> CGRect? {
    let w = image.width, h = image.height
    var a = [UInt8](repeating: 0, count: w * h)
    _ = a.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)?
            .draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    var minX = w, minR = h, maxX = -1, maxR = -1
    for y in 0..<h { for x in 0..<w where a[y * w + x] > 38 {
        minX = min(minX, x); maxX = max(maxX, x); minR = min(minR, y); maxR = max(maxR, y) } }
    guard maxX >= 0 else { return nil }
    return CGRect(x: CGFloat(minX), y: CGFloat(h - 1 - maxR),
                  width: CGFloat(maxX - minX + 1), height: CGFloat(maxR - minR + 1))
}

var frames: [Frame] = []
for url in (try! FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
    .filter({ $0.pathExtension.lowercased() == "png" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    let name = url.deletingPathExtension().lastPathComponent
    guard let sep = name.lastIndex(of: "_"), Int(name[name.index(after: sep)...]) != nil,
          let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let content = contentBounds(image) else { continue }
    frames.append(Frame(url: url, action: String(name[name.startIndex..<sep]), image: image,
                        canvas: CGSize(width: image.width, height: image.height), content: content))
}
guard !frames.isEmpty else { print("кадров не найдено"); exit(1) }

func factor(_ f: Frame) -> CGFloat { factors[f.action] ?? 1 }

// Холст — по самому крупному содержимому после пересчёта, плюс поля.
var halfWidth: CGFloat = 0, top: CGFloat = 0
for f in frames {
    let s = factor(f)
    let centre = f.canvas.width / 2
    halfWidth = max(halfWidth, max(abs(f.content.minX - centre), abs(f.content.maxX - centre)) * s)
    top = max(top, (f.content.origin.y + f.content.height) * s)
}
let margin: CGFloat = 6
let canvas = CGSize(width: (halfWidth * 2 + margin * 2).rounded(.up), height: (top + margin).rounded(.up))
print("холст: \(Int(frames[0].canvas.width))x\(Int(frames[0].canvas.height)) -> \(Int(canvas.width))x\(Int(canvas.height))")

var byAction: [String: (lo: Int, hi: Int)] = [:]
for f in frames {
    let h = Int((f.content.height * factor(f)).rounded())
    let cur = byAction[f.action] ?? (Int.max, 0)
    byAction[f.action] = (min(cur.lo, h), max(cur.hi, h))
}
print("рост персонажа после пересчёта:")
for (a, v) in byAction.sorted(by: { $0.key < $1.key }) {
    print(String(format: "  %-10@ x%.3f  %d–%d", a as NSString, factor(frames.first { $0.action == a }!), v.lo, v.hi))
}
guard !dryRun else { print("(пробный прогон, файлы не тронуты)"); exit(0) }

for f in frames {
    let s = factor(f)
    let w = Int(canvas.width), h = Int(canvas.height)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.interpolationQuality = .high
    let drawn = CGSize(width: f.canvas.width * s, height: f.canvas.height * s)
    ctx.draw(f.image, in: CGRect(x: canvas.width / 2 - drawn.width / 2, y: 0,
                                 width: drawn.width, height: drawn.height))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: w, height: h)
    try! rep.representation(using: .png, properties: [:])!.write(to: f.url)
}
print("готово, кадров: \(frames.count)")
