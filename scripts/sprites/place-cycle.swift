import AppKit
import CoreImage

// Перенос цикла анимации из полноразмерных кадров (например, из видео) на
// холст пака.
//
// Для всех кадров цикла преобразование одно: общая рамка содержимого, один
// масштаб, один сдвиг. Персонаж в видео идёт на месте при неподвижной камере,
// поэтому центрирование каждого кадра по его собственным границам дёргало бы
// тело вбок, когда вытягиваются лапы, а посадка каждого кадра на землю
// съела бы покачивание. Земля — самая нижняя лапа за цикл.
//
//   swift place-cycle.swift <кадры> <пак> <действие> <масштаб> [--outline 3] [--sharpen 0.5] [--dry-run]
//
// Масштабирование — один проход Ланцошем, перенос на холст — целым сдвигом.
//
// При сильном уменьшении (у видео — восьмикратном) тонкий контур растворяется
// в заливке: персонаж светлеет и теряет границы. `--outline r` утолщает тёмные
// линии на полном разрешении до уменьшения (минимум по цвету в радиусе r
// пикселей, альфа остаётся исходной), `--sharpen k` добавляет лёгкую резкость
// после. Значения 3 и 0.5 подобраны на корги из видео: доля тёмных пикселей
// контура 9.5% против 10.4% у idle; при r=5 глаз уже слипается с мордой.

let src = URL(fileURLWithPath: CommandLine.arguments[1])
let pack = URL(fileURLWithPath: CommandLine.arguments[2])
let action = CommandLine.arguments[3]
let scale = CGFloat(Double(CommandLine.arguments[4])!)
let dryRun = CommandLine.arguments.contains("--dry-run")
func option(_ name: String) -> Double? {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count else { return nil }
    return Double(CommandLine.arguments[i + 1])
}
let outline = option("--outline") ?? 0
let sharpen = option("--sharpen") ?? 0

func load(_ url: URL) -> CGImage { NSImage(contentsOf: url)!.cgImage(forProposedRect: nil, context: nil, hints: nil)! }

/// Границы непрозрачного; начало — левый верхний угол, как у CGImage.cropping.
func bounds(_ im: CGImage) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    let w = im.width, h = im.height
    var a = [UInt8](repeating: 0, count: w*h)
    _ = a.withUnsafeMutableBytes { r in
        CGContext(data: r.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
            .draw(im, in: CGRect(x: 0, y: 0, width: w, height: h)) }
    var mnX = w, mxX = -1, mnY = h, mxY = -1
    for y in 0..<h { for x in 0..<w where a[y*w+x] > 8 {
        mnX = min(mnX, x); mxX = max(mxX, x); mnY = min(mnY, y); mxY = max(mxY, y) } }
    return mxX < 0 ? nil : (mnX, mnY, mxX, mxY)
}

let files = (try! FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: nil))
    .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
let frames = files.map(load)

var u = (minX: Int.max, minY: Int.max, maxX: Int.min, maxY: Int.min)
for f in frames { if let b = bounds(f) { u = (min(u.minX, b.minX), min(u.minY, b.minY), max(u.maxX, b.maxX), max(u.maxY, b.maxY)) } }

// Небольшой запас вокруг рамки — чтобы кромка Ланцоша не обрезалась.
let margin = 8
let crop = CGRect(x: max(0, u.minX - margin), y: max(0, u.minY - margin),
                  width: (u.maxX - u.minX + 1) + margin * 2, height: (u.maxY - u.minY + 1) + margin * 2)

let sample = (try! FileManager.default.contentsOfDirectory(at: pack, includingPropertiesForKeys: nil))
    .first { $0.pathExtension == "png" && !$0.lastPathComponent.hasPrefix(action + "_") }!
let canvas = (w: load(sample).width, h: load(sample).height)

let outW = Int((crop.width * scale).rounded()), outH = Int((crop.height * scale).rounded())
let x = (canvas.w - outW) / 2
// Нижняя кромка рамки (самая нижняя лапа цикла) ложится на низ холста.
let y = -Int((CGFloat(margin) * scale).rounded())
print("кадров: \(frames.count), рамка цикла \(u.maxX - u.minX + 1)x\(u.maxY - u.minY + 1), после масштаба \(outW)x\(outH)")
print("холст пака: \(canvas.w)x\(canvas.h), сдвиг x=\(x) y=\(y)")

guard outW <= canvas.w, outH + y <= canvas.h else { print("не помещается на холст — правка отменена"); exit(1) }
guard !dryRun else { print("(пробный прогон, файлы не тронуты)"); exit(0) }

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ci = CIContext(options: [.workingColorSpace: srgb, .outputColorSpace: srgb])

/// Утолщение тёмных линий: минимум по цвету в радиусе r, альфа исходная.
func thickenLines(_ image: CIImage, radius: Double) -> CIImage {
    guard radius > 0 else { return image }
    let min = CIFilter(name: "CIMorphologyMinimum")!
    min.setValue(image, forKey: kCIInputImageKey)
    min.setValue(radius, forKey: kCIInputRadiusKey)
    let blend = CIFilter(name: "CIBlendWithAlphaMask")!
    blend.setValue(min.outputImage!.cropped(to: image.extent), forKey: kCIInputImageKey)
    blend.setValue(image, forKey: kCIInputBackgroundImageKey)
    blend.setValue(image, forKey: kCIInputMaskImageKey)
    return blend.outputImage!.cropped(to: image.extent)
}
// Старые кадры действия убираем целиком: иначе лишние с большими номерами
// остались бы в цикле.
for old in (try! FileManager.default.contentsOfDirectory(at: pack, includingPropertiesForKeys: nil))
    where old.lastPathComponent.hasPrefix(action + "_") && old.pathExtension == "png" {
    try! FileManager.default.removeItem(at: old)
}
for (i, f) in frames.enumerated() {
    let part = f.cropping(to: crop)!
    let filter = CIFilter(name: "CILanczosScaleTransform")!
    filter.setValue(thickenLines(CIImage(cgImage: part), radius: outline), forKey: kCIInputImageKey)
    filter.setValue(Double(scale), forKey: kCIInputScaleKey)
    filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
    var reduced = filter.outputImage!
    if sharpen > 0 {
        let unsharp = CIFilter(name: "CIUnsharpMask")!
        unsharp.setValue(reduced, forKey: kCIInputImageKey)
        unsharp.setValue(0.8, forKey: kCIInputRadiusKey)
        unsharp.setValue(sharpen, forKey: kCIInputIntensityKey)
        reduced = unsharp.outputImage!.cropped(to: filter.outputImage!.extent)
    }
    let small = ci.createCGImage(reduced, from: CGRect(x: 0, y: 0, width: outW, height: outH),
                                 format: .RGBA8, colorSpace: srgb)!

    let c = CGContext(data: nil, width: canvas.w, height: canvas.h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.clear(CGRect(x: 0, y: 0, width: canvas.w, height: canvas.h))
    c.interpolationQuality = .none
    c.draw(small, in: CGRect(x: x, y: y, width: outW, height: outH))
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    rep.size = NSSize(width: canvas.w, height: canvas.h)
    try! rep.representation(using: .png, properties: [:])!
        .write(to: pack.appendingPathComponent(String(format: "%@_%02d.png", action, i)))
}
print("готово: \(frames.count) кадров \(action)_00…\(String(format: "%02d", frames.count - 1))")
