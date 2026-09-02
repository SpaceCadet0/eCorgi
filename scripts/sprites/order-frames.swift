import AppKit

// Подбор порядка кадров в цикле.
//
// Генератор нередко выдаёт позы вразнобой. Порядок здесь ищется по похожести
// соседей: между соседними кадрами циклической анимации разница должна быть
// минимальной, иначе на стыке виден рывок. Задача сводится к поиску
// кратчайшего замкнутого маршрута по кадрам — жадный обход плюс 2-opt.

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let prefix = CommandLine.arguments[2]
let outDir = CommandLine.arguments.count > 3 ? URL(fileURLWithPath: CommandLine.arguments[3]) : nil
var startAt = 0
if let i = CommandLine.arguments.firstIndex(of: "--start"), i + 1 < CommandLine.arguments.count {
    startAt = Int(CommandLine.arguments[i + 1]) ?? 0
}

let files = (try! FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
    .filter { $0.pathExtension == "png" && $0.lastPathComponent.hasPrefix(prefix + "_") }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

func rgba(_ url: URL) -> (w: Int, h: Int, data: [UInt8])? {
    guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    data.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
            .draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (w, h, data)
}

let frames = files.compactMap { rgba($0) }
guard frames.count == files.count, frames.count > 2 else { print("кадры не прочитались"); exit(1) }
let n = frames.count

/// Насколько два кадра непохожи. Кадры уже выровнены по холсту.
var dist = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
for i in 0..<n {
    for j in (i+1)..<n {
        var sum = 0.0
        for k in stride(from: 0, to: frames[i].data.count, by: 4) {
            sum += abs(Double(frames[i].data[k+3]) - Double(frames[j].data[k+3]))          // силуэт
            sum += 0.3 * abs(Double(frames[i].data[k]) - Double(frames[j].data[k]))        // цвет
        }
        let d = sum / Double(frames[i].data.count / 4)
        dist[i][j] = d; dist[j][i] = d
    }
}

func cost(_ order: [Int]) -> Double {
    (0..<order.count).reduce(0) { $0 + dist[order[$1]][order[($1 + 1) % order.count]] }
}

// Жадный обход от каждого старта, дальше 2-opt.
var best = Array(0..<n)
var bestCost = cost(best)
for start in 0..<n {
    var visited = [Bool](repeating: false, count: n)
    var order = [start]
    visited[start] = true
    while order.count < n {
        let last = order.last!
        var pick = -1, pickD = Double.infinity
        for j in 0..<n where !visited[j] && dist[last][j] < pickD { pick = j; pickD = dist[last][j] }
        visited[pick] = true
        order.append(pick)
    }
    var improved = true
    while improved {
        improved = false
        for a in 0..<n - 1 {
            for b in (a + 1)..<n {
                var candidate = order
                candidate.replaceSubrange(a...b, with: order[a...b].reversed())
                if cost(candidate) < cost(order) - 1e-9 { order = candidate; improved = true }
            }
        }
    }
    let c = cost(order)
    if c < bestCost { best = order; bestCost = c }
}

// Разворот на нужную стартовую позу.
if let at = best.firstIndex(of: startAt) { best = Array(best[at...] + best[..<at]) }

let original = Array(0..<n)
print(String(format: "стоимость: исходный порядок %.1f, подобранный %.1f", cost(original), bestCost))
print("порядок (номера исходных кадров): \(best.map(String.init).joined(separator: " "))")
print("разрывы между соседями:")
for i in 0..<best.count {
    let a = best[i], b = best[(i + 1) % best.count]
    print(String(format: "  %02d -> %02d : %.1f", a, b, dist[a][b]))
}

guard let outDir else { exit(0) }
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (position, source) in best.enumerated() {
    let to = outDir.appendingPathComponent(String(format: "%@_%02d.png", prefix, position))
    try? FileManager.default.removeItem(at: to)
    try! FileManager.default.copyItem(at: files[source], to: to)
}
print("записано кадров: \(best.count) -> \(outDir.path)")
