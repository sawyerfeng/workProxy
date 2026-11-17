import XCTest
@testable import WorkProxy

final class NetworkMonitorTests: XCTestCase {
    @MainActor
    func testOnlyConnectedPhysicalInterfacesCanBeSelected() {
        XCTAssertNil(NetworkMonitor.physicalInterface(primary: "en0", candidates: [], wifi: "en0"))
        XCTAssertNil(NetworkMonitor.physicalInterface(primary: "utun3", candidates: ["utun3", "lo0"], wifi: "en0"))
        XCTAssertEqual(NetworkMonitor.physicalInterface(primary: "en7", candidates: ["en0", "en7"], wifi: "en0"), "en7")
        XCTAssertEqual(NetworkMonitor.physicalInterface(primary: "utun3", candidates: ["utun3", "en0"], wifi: "en0"), "en0")
        XCTAssertEqual(NetworkMonitor.physicalInterface(primary: "en0", candidates: ["en7"], wifi: "en0"), "en7")
    }
}
