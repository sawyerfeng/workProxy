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
        NSColor(srgbRed: 0.23, green: 0.55, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.06, green: 0.27, blue: 0.70, alpha: 1)
    ])!
    gradient.draw(in: background, angle: -90)

    // SF Symbol 使用调色板配置直接画成白色。
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let symbol = NSImage(systemSymbolName: "network",
                               accessibilityDescription: "workProxy")?
        .withSymbolConfiguration(symbolConfig) else {
        fatalError("无法加载 network 符号")
    }
    let symbolSize = symbol.size
    symbol.draw(in: NSRect(x: (size - symbolSize.width) / 2,
                           y: (size - symbolSize.height) / 2,
                           width: symbolSize.width,
                           height: symbolSize.height))

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
