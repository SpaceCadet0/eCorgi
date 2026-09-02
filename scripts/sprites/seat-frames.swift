import AppKit

// Посадка кадров на землю: убирает зазор между нижней точкой рисунка и
// нижней кромкой холста. Именно к этой кромке движок ставит лапы питомца,
// поэтому зазор выглядит как парение над полом.
//
// Режимы:
//   --each   каждый кадр садится на землю сам по себе. Для шага это верно:
//            опорная лапа не должна отрываться от земли.
//   --cycle  весь цикл опускается на общую величину — самый низкий кадр
//            садится на землю, остальные сохраняют своё превышение.

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let prefix = CommandLine.arguments[2]
let perFrame = CommandLine.arguments.count < 4 || CommandLine.arguments[3] != "--cycle"
let dryRun = CommandLine.arguments.contains("--dry-run")

let files = (try! FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
    .filter { $0.pathExtension == "png" && $0.lastPathComponent.hasPrefix(prefix + "_") }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

/// Сколько пустых строк осталось под рисунком.
func gapBelow(_ image: CGImage) -> Int {
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h)
    _ = data.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)?
            .draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    var lowest = -1
    for y in stride(from: h - 1, through: 0, by: -1) {
        for x in 0..<w where data[y * w + x] > 38 { lowest = y; break }
        if lowest >= 0 { break }
    }
    return lowest < 0 ? 0 : h - 1 - lowest
}

var frames: [(url: URL, image: CGImage, gap: Int)] = []
for url in files {
    guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    frames.append((url, image, gapBelow(image)))
}
guard !frames.isEmpty else { print("кадров не найдено"); exit(1) }

let common = frames.map(\.gap).min() ?? 0
print("режим: \(perFrame ? "каждый кадр сам по себе" : "весь цикл на \(common)")")

for f in frames {
    let drop = perFrame ? f.gap : common
    let name = f.url.deletingPathExtension().lastPathComponent
    print("  \(name): зазор \(f.gap) -> \(f.gap - drop)")
    guard !dryRun, drop > 0 else { continue }

    let w = f.image.width, h = f.image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
    // Сдвиг целыми пикселями: без интерполяции, рисунок не мылится.
    ctx.draw(f.image, in: CGRect(x: 0, y: -drop, width: w, height: h))

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: w, height: h)
    try! rep.representation(using: .png, properties: [:])!.write(to: f.url)
}
print(dryRun ? "(пробный прогон, файлы не тронуты)" : "готово")
