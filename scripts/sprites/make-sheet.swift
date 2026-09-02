import AppKit

// Сборка спрайт-листа из отдельных кадров: обратная операция к split-sheet.
// Кадры выстраиваются в один ряд слева направо, каждый — в клетке общего
// размера, выровненный по низу и центру, как их ставит движок.

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let out = URL(fileURLWithPath: CommandLine.arguments[2])
var gap = 10
if let i = CommandLine.arguments.firstIndex(of: "--gap"), i + 1 < CommandLine.arguments.count {
    gap = Int(CommandLine.arguments[i + 1]) ?? gap
}

/// Число в конце имени, после последнего «_». По нему и идёт порядок:
/// по алфавиту «_10» встало бы перед «_2».
func frameIndex(_ name: String) -> Int? {
    guard let separator = name.lastIndex(of: "_") else { return nil }
    return Int(name[name.index(after: separator)...])
}

let files = (try! FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { a, b in
        let na = a.deletingPathExtension().lastPathComponent
        let nb = b.deletingPathExtension().lastPathComponent
        switch (frameIndex(na), frameIndex(nb)) {
        case let (x?, y?) where x != y: return x < y
        default: return na < nb
        }
    }

let images = files.compactMap { NSImage(contentsOf: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
guard !images.isEmpty else { print("кадров не найдено"); exit(1) }

let cell = CGSize(width: CGFloat(images.map(\.width).max()!),
                  height: CGFloat(images.map(\.height).max()!))
let width = Int(cell.width) * images.count + gap * (images.count - 1)
let height = Int(cell.height)
print("кадров: \(images.count), клетка \(Int(cell.width))x\(Int(cell.height)), лист \(width)x\(height)")
print("порядок: \(files.prefix(3).map { $0.deletingPathExtension().lastPathComponent }.joined(separator: ", ")) … \(files.last!.deletingPathExtension().lastPathComponent)")

let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))

for (i, image) in images.enumerated() {
    let cellX = CGFloat(i * (Int(cell.width) + gap))
    // По низу и центру клетки — так же, как спрайт ставит движок.
    let x = cellX + (cell.width - CGFloat(image.width)) / 2
    ctx.draw(image, in: CGRect(x: x, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
}

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = NSSize(width: width, height: height)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("готово: \(out.path)")
