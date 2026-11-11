import XCTest
import UserNotifications
@testable import WorkProxy

final class PermissionTests: XCTestCase {
    func testPermissionStatesAreDistinguishable() {
        XCTAssertEqual(UNAuthorizationStatus.notDetermined.permissionLabel, "未申请")
        XCTAssertEqual(UNAuthorizationStatus.denied.permissionLabel, "未授权")
        for status in [UNAuthorizationStatus.authorized, .provisional] {
            XCTAssertEqual(status.permissionLabel, "已授权")
        }
    }
}
