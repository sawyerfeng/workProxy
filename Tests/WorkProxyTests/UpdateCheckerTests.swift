import CryptoKit
import XCTest
@testable import WorkProxy

final class UpdateCheckerTests: XCTestCase {
    func testReleaseUpdatesRequireSignedFeedAndArchiveBeforeExtraction() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let url = try XCTUnwrap(URL(string: try XCTUnwrap(info["SUFeedURL"] as? String)))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/sawyerfeng/workProxy/releases/latest/download/appcast.xml")
        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        let key = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(info["SUPublicEDKey"] as? String)))
        XCTAssertNoThrow(try Curve25519.Signing.PublicKey(rawRepresentation: key))
    }

    @MainActor
    func testCommandLineAndTestsDoNotStartUpdater() {
        let checker = UpdateChecker()
        checker.start()
        XCTAssertFalse(checker.canCheckForUpdates)
    }
}
