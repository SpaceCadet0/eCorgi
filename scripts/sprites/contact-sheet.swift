import AppKit

// Контрольный лист: все кадры действия подряд, с линией земли и номерами.
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let prefix = CommandLine.arguments[2]
let out = URL(fileURLWithPath: CommandLine.arguments[3])

let files = (try! FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
    .filter { $0.lastPathComponent.hasPrefix(prefix + "_") && $0.pathExtension == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

let images = files.compactMap { NSImage(contentsOf: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
guard let first = images.first else { exit(1) }
let cw = first.width, ch = first.height
let cols = 7, rows = (images.count + cols - 1) / cols
let pad = 8, labelH = 16
let W = cols * (cw + pad) + pad, H = rows * (ch + pad + labelH) + pad

let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

for (i, image) in images.enumerated() {
    let col = i % cols, row = i / cols
    let x = pad + col * (cw + pad)
    let y = H - (row + 1) * (ch + pad + labelH)
    // Клетка и линия земли.
    ctx.setFillColor(CGColor(red: 0.18, green: 0.19, blue: 0.22, alpha: 1))
    ctx.fill(CGRect(x: x, y: y + labelH, width: cw, height: ch))
    ctx.setStrokeColor(CGColor(red: 0.45, green: 0.5, blue: 0.6, alpha: 1))
    ctx.setLineWidth(1)
    ctx.stroke(CGRect(x: Double(x) + 0.5, y: Double(y + labelH) + 0.5, width: Double(cw) - 1, height: 0.5))
    ctx.draw(image, in: CGRect(x: x, y: y + labelH, width: cw, height: ch))

    let label = files[i].deletingPathExtension().lastPathComponent as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.75, alpha: 1)
    ]
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    label.draw(at: NSPoint(x: x, y: y + 2), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
}

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("контрольный лист: \(out.path) (\(W)x\(H), кадров \(images.count))")
