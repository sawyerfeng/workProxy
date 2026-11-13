import AppKit
import SwiftUI
import XCTest
import WorkProxyCore
@testable import WorkProxy

final class RuleEditorLayoutTests: XCTestCase {
    @MainActor
    func testEditorStaysCompactAndLeavesRoomForLocationControls() throws {
        let network = NetworkIdentity(interfaceName: "en0", kind: .wifi, ssid: "Xiaoyang 的 iPhone")
        let locatedRule = Rule(name: "办公室", network: .wifi(ssid: "Office"),
                               place: PlaceCondition(label: "办公室", latitude: 31, longitude: 121, radiusMeters: 500),
                               action: .off)
        for (name, rule, current, maximumHeight) in [
            ("compact", nil, network, 500.0),
            ("network", nil, nil, 600.0),
            ("location", locatedRule, network, 700.0)
        ] as [(String, Rule?, NetworkIdentity?, CGFloat)] {
            for scheme in [ColorScheme.light, .dark] {
                var saved = false
                let view = RuleEditorView(existing: rule, services: [], currentNetwork: current,
                                          knownWiFiNetworks: ["Office", "Xiaoyang 的 iPhone"],
                                          locationService: LocationService(), onRefreshWiFi: {},
                                          onSave: { _ in saved = true; return nil })
                    .environment(\.colorScheme, scheme)
                let host = NSHostingView(rootView: view)
                XCTAssertEqual(host.fittingSize.width, 520)
                XCTAssertLessThan(host.fittingSize.height, maximumHeight)
                if let directory = ProcessInfo.processInfo.environment["WORKPROXY_PREVIEW_DIR"] {
                    host.frame = NSRect(origin: .zero, size: host.fittingSize)
                    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = host
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("editor-\(name)-\(scheme).png"))
                }
                XCTAssertFalse(saved)
            }
        }
    }
}
