import AppKit
import CoreGraphics

func drawIcon(size s: CGFloat, ctx: CGContext) {
    let inset = s * 0.085
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.2237

    // 圆角底板 + 渐变
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let top = NSColor(calibratedRed: 0.09, green: 0.33, blue: 0.82, alpha: 1).cgColor
    let bottom = NSColor(calibratedRed: 0.04, green: 0.66, blue: 0.70, alpha: 1).cgColor
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [top, bottom] as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    }
    ctx.restoreGState()

    // 表盘
    let center = CGPoint(x: s / 2, y: s * 0.42)
    let r = s * 0.27
    let start = CGFloat.pi * 210 / 180
    let end = CGFloat.pi * -30 / 180

    ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.30).cgColor)
    ctx.setLineWidth(s * 0.085)
    ctx.addArc(center: center, radius: r, startAngle: start, endAngle: end, clockwise: true)
    ctx.strokePath()

    // 已用进度弧（约 68%）
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.addArc(center: center, radius: r,
               startAngle: start, endAngle: start - (start - end) * 0.68, clockwise: true)
    ctx.strokePath()

    // 指针
    let angle = start - (start - end) * 0.68
    let tip = CGPoint(x: center.x + cos(angle) * r * 0.82, y: center.y + sin(angle) * r * 0.82)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(s * 0.055)
    ctx.move(to: center)
    ctx.addLine(to: tip)
    ctx.strokePath()

    // 中心圆点
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: center.x - s * 0.045, y: center.y - s * 0.045,
                               width: s * 0.09, height: s * 0.09))

    // 底部信号点（三格）
    let dotR = s * 0.026
    for (i, alpha) in [0.45, 0.72, 1.0].enumerated() {
        ctx.setFillColor(NSColor.white.withAlphaComponent(CGFloat(alpha)).cgColor)
        let x = s / 2 + CGFloat(i - 1) * s * 0.11
        ctx.fillEllipse(in: CGRect(x: x - dotR, y: s * 0.80 - dotR, width: dotR * 2, height: dotR * 2))
    }
}

func renderPNG(pixels: Int, to path: String) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if let ctx = NSGraphicsContext.current?.cgContext {
        drawIcon(size: CGFloat(pixels), ctx: ctx)
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let mapping: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for m in mapping {
    renderPNG(pixels: m.px, to: outDir + "/" + m.name)
}
print("iconset written to \(outDir)")
