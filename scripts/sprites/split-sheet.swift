import AppKit

// Разбор спрайт-листа на кадры.
// Кадры вырезаются по связным областям, а не по равным долям ширины: доли
// не сходятся (2200/19 не целое), а области соседних кадров соприкасаются,
// поэтому обрезка прямоугольником захватила бы кусок соседа.

let sheetURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
let prefix = CommandLine.arguments[3]
let canvas = CGSize(width: Double(CommandLine.arguments[4])!, height: Double(CommandLine.arguments[5])!)
let targetHeight = CGFloat(Double(CommandLine.arguments[6])!)

let image = NSImage(contentsOf: sheetURL)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let w = image.width, h = image.height

// Пиксели листа целиком.
var pixels = [UInt8](repeating: 0, count: w * h * 4)
pixels.withUnsafeMutableBytes { raw in
    CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
        .draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
}
func alphaAt(_ i: Int) -> UInt8 { pixels[i * 4 + 3] }

// Разметка связных областей.
var label = [Int32](repeating: -1, count: w * h)
struct Blob { var minX = Int.max; var maxX = -1; var minY = Int.max; var maxY = -1; var count = 0 }
var blobs: [Blob] = []
for start in 0..<(w * h) where alphaAt(start) > 38 && label[start] < 0 {
    let id = Int32(blobs.count)
    var b = Blob()
    var stack = [start]
    label[start] = id
    while let p = stack.popLast() {
        let x = p % w, y = p / w
        b.minX = min(b.minX, x); b.maxX = max(b.maxX, x)
        b.minY = min(b.minY, y); b.maxY = max(b.maxY, y)
        b.count += 1
        for (dx, dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
            let q = ny * w + nx
            if alphaAt(q) > 38 && label[q] < 0 { label[q] = id; stack.append(q) }
        }
    }
    blobs.append(b)
}

let frames = blobs.enumerated().filter { $0.element.count > 200 }.sorted { $0.element.minX < $1.element.minX }
print("кадров найдено: \(frames.count)")

// Общая линия земли — самая нижняя точка цикла. Относительно неё
// сохраняется покачивание: кадры, где лапы выше, останутся выше.
let groundY = frames.map(\.element.maxY).max()!
let tallest = groundY - frames.map(\.element.minY).min()! + 1
let scale = targetHeight / CGFloat(tallest)
print("самый высокий кадр над землёй: \(tallest) -> коэффициент \(String(format: "%.3f", scale))")

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for (index, item) in frames.enumerated() {
    let (id, b) = (Int32(item.offset), item.element)
    let bw = b.maxX - b.minX + 1, bh = b.maxY - b.minY + 1

    // Только пиксели этой области — сосед не попадёт.
    var cut = [UInt8](repeating: 0, count: bw * bh * 4)
    for y in b.minY...b.maxY {
        for x in b.minX...b.maxX where label[y * w + x] == id {
            let from = (y * w + x) * 4, to = ((y - b.minY) * bw + (x - b.minX)) * 4
            cut[to] = pixels[from]; cut[to+1] = pixels[from+1]
            cut[to+2] = pixels[from+2]; cut[to+3] = pixels[from+3]
        }
    }
    let piece = cut.withUnsafeMutableBytes { raw -> CGImage? in
        CGContext(data: raw.baseAddress, width: bw, height: bh, bitsPerComponent: 8, bytesPerRow: bw * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }
    guard let piece else { continue }

    let out = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    out.clear(CGRect(origin: .zero, size: canvas))
    out.interpolationQuality = .high
    let drawn = CGSize(width: CGFloat(bw) * scale, height: CGFloat(bh) * scale)
    // Отступ от земли сохраняется, по горизонтали кадр центрируется:
    // это бег на месте.
    let liftAboveGround = CGFloat(groundY - b.maxY) * scale
    out.draw(piece, in: CGRect(x: (canvas.width - drawn.width) / 2, y: liftAboveGround,
                               width: drawn.width, height: drawn.height))

    let rep = NSBitmapImageRep(cgImage: out.makeImage()!)
    rep.size = NSSize(width: canvas.width, height: canvas.height)
    let name = String(format: "%@_%02d.png", prefix, index)
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    print("  \(name): \(Int(drawn.width))x\(Int(drawn.height)), над землёй \(Int(liftAboveGround))")
}
