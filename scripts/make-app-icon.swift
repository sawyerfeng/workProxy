#!/usr/bin/env swift
// 生成 workProxy 的 .icns 应用图标。仅在需要更新图标时手动运行：
//   swift scripts/make-app-icon.swift Resources/AppIcon.icns

import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.icns"
let outputURL = URL(fileURLWithPath: outputPath)
let iconsetURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("workProxy-\(UUID().uuidString).iconset", isDirectory: true)

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconsetURL) }

func renderPNG(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        fatalError("无法创建位图")
    }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill(using: .copy)

    // macOS 图标安全区：四周留白，圆角约为边长的 22.5%。
    let inset = size * 0.075
    let rect = NSRect(x: inset, y: inset,
                      width: size - inset * 2, height: size - inset * 2)
    let radius = size * 0.225
    let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.12, green: 0.23, blue: 0.25, alpha: 1),
        NSColor(srgbRed: 0.035, green: 0.075, blue: 0.10, alpha: 1)
    ])!
    gradient.draw(in: background, angle: -65)
    NSColor(srgbRed: 0.60, green: 0.88, blue: 0.80, alpha: 0.22).setStroke()
    background.lineWidth = size * 0.008
    background.stroke()

    let mint = NSColor(srgbRed: 0.48, green: 0.94, blue: 0.77, alpha: 1)
    let pale = NSColor(srgbRed: 0.84, green: 0.94, blue: 0.91, alpha: 1)
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: size * x, y: size * y)
    }

    // 两条相向路径保留开放空间，在 16 px 下仍能辨识切换方向。
    let upper = NSBezierPath()
    upper.move(to: point(0.28, 0.53))
    upper.curve(to: point(0.43, 0.67),
                controlPoint1: point(0.28, 0.62), controlPoint2: point(0.34, 0.67))
    upper.line(to: point(0.72, 0.67))
    upper.move(to: point(0.62, 0.77))
    upper.line(to: point(0.72, 0.67))
    upper.line(to: point(0.62, 0.57))
    upper.lineWidth = size * 0.067
    upper.lineCapStyle = .round
    upper.lineJoinStyle = .round
    mint.setStroke()
    upper.stroke()

    let lower = NSBezierPath()
    lower.move(to: point(0.72, 0.47))
    lower.curve(to: point(0.57, 0.33),
                controlPoint1: point(0.72, 0.38), controlPoint2: point(0.66, 0.33))
    lower.line(to: point(0.28, 0.33))
    lower.move(to: point(0.38, 0.43))
    lower.line(to: point(0.28, 0.33))
    lower.line(to: point(0.38, 0.23))
    lower.lineWidth = size * 0.067
    lower.lineCapStyle = .round
    lower.lineJoinStyle = .round
    pale.setStroke()
    lower.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

if CommandLine.arguments.count > 2 {
    try renderPNG(pixels: 512)
        .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in entries {
    try renderPNG(pixels: pixels).write(to: iconsetURL.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("iconutil 失败，状态码 \(process.terminationStatus)")
}
print("已生成 \(outputURL.path)")
