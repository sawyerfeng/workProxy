import AppKit
import SwiftUI
import XCTest
@testable import WorkProxy

final class ConsolePaletteTests: XCTestCase {
    func testTextAndActionColorsRemainReadableInBothAppearances() throws {
        for scheme in [ColorScheme.light, .dark] {
            let palette = ConsolePalette(scheme: scheme)
            let surface = try components(palette.surface)
            let canvas = try components(palette.canvas)
            for foreground in [palette.text, palette.secondary] {
                let color = try components(foreground)
                XCTAssertGreaterThanOrEqual(contrast(color, surface), 4.5, "\(scheme) text on surface")
                XCTAssertGreaterThanOrEqual(contrast(color, canvas), 4.5, "\(scheme) text on canvas")
            }
            for foreground in [palette.mint, palette.coral] {
                let color = try components(foreground)
                let badge = zip(color, surface).map { 0.12 * $0 + 0.88 * $1 }
                XCTAssertGreaterThanOrEqual(contrast(color, badge), 4.5, "\(scheme) action badge")
            }
        }
    }

    private func components(_ color: Color) throws -> [Double] {
        let rgb = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB))
        return [Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent)]
    }

    private func contrast(_ a: [Double], _ b: [Double]) -> Double {
        func luminance(_ rgb: [Double]) -> Double {
            let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
