import XCTest
@testable import WorkProxyCore

final class SettingsStoreTests: XCTestCase {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkProxySettingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sampleSettings() -> AppSettings {
        let office = PlaceCondition(label: "办公室", address: "上海市",
                                    latitude: 31.2304, longitude: 121.4737,
                                    radiusMeters: 120)
        return AppSettings(
            endpoint: ProxyEndpoint(host: "127.0.0.1", port: 7890),
            rules: [
                Rule(name: "办公室 Wi-Fi", network: .wifi(ssid: "Office"),
                     place: office, action: .on),
                Rule(name: "USB 网卡", network: .wired(interfaceName: "en7"),
                     action: .off, enabled: false)
            ],
            paused: true,
            launchAtLogin: false,
            hasCompletedOnboarding: true
        )
    }

    func testRoundTripRulesIncludingWifiWiredLocationAndActions() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONSettingsStore(url: directory.appendingPathComponent("settings.json"))
        let settings = sampleSettings()

        try store.save(settings)
        let loaded = try store.load()

        XCTAssertEqual(loaded, settings)
        XCTAssertEqual(loaded.rules.map(\.network),
                       [.wifi(ssid: "Office"), .wired(interfaceName: "en7")])
        XCTAssertEqual(loaded.rules.first?.place?.radiusMeters, 120)
        XCTAssertEqual(loaded.rules.map(\.action), [.on, .off])
    }

    func testMissingFileReturnsDefault() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONSettingsStore(url: directory.appendingPathComponent("missing.json"))

        XCTAssertEqual(try store.load(), .default)
    }

    func testCorruptFileReturnsDefaultAndLeavesCorruptBackup() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        try Data("{ this is not json".utf8).write(to: url)
        let store = JSONSettingsStore(url: url)

        XCTAssertEqual(try store.load(), .default)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "corrupt file should be renamed away")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let backups = names.filter {
            $0.hasPrefix("settings.corrupt-") && $0.hasSuffix(".json")
        }
        XCTAssertEqual(backups.count, 1, "expected exactly one corrupt backup, got \(names)")
    }

    func testCorruptFileWithWrongSchemaReturnsDefault() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        try Data(#"{"rules": "not-an-array"}"#.utf8).write(to: url)
        let store = JSONSettingsStore(url: url)

        XCTAssertEqual(try store.load(), .default)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("settings.corrupt-") })
    }

    func testSaveCreatesDirectory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("deeper", isDirectory: true)
            .appendingPathComponent("settings.json")
        let store = JSONSettingsStore(url: url)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))

        let settings = sampleSettings()
        try store.save(settings)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try store.load(), settings)
    }

    func testSavedFileIsOwnerReadableOnly() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let store = JSONSettingsStore(url: url)

        try store.save(sampleSettings())

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)
    }

    func testDefaultURLPointsToApplicationSupportWorkProxy() {
        let url = JSONSettingsStore.defaultURL()

        XCTAssertEqual(url.lastPathComponent, "settings.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "workProxy")
        XCTAssertTrue(url.path.contains("Application Support"))
    }

    func testInMemoryStoreRecordsSaves() throws {
        let store = InMemorySettingsStore(AppSettings(paused: false))

        XCTAssertEqual(try store.load(), AppSettings(paused: false))

        let first = AppSettings(paused: true)
        let second = AppSettings(paused: false, launchAtLogin: false)
        try store.save(first)
        try store.save(second)

        XCTAssertEqual(try store.load(), second)
        XCTAssertEqual(store.saveCount, 2)
        XCTAssertEqual(store.savedSettings, [first, second])
    }
}
