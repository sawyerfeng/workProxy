import XCTest
import WorkProxyCore
@testable import WorkProxy

private final class ControllerStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let mode = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let status = mode == "Bearer unauthorized" ? 401 : 200
        let body = mode == "Bearer malformed" ? "{}" :
            #"{"tun":{"enable":\#(mode == "Bearer still-on" ? "true" : "false")}}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class FlClashControllerTests: XCTestCase {
    func testRequestAndLocalBoundary() throws {
        let config = FlClashSettings(address: "http://127.0.0.1:9090", secret: "test")
        let request = try FlClashController.request(config, method: "PATCH")
        XCTAssertEqual(request.url?.path, "/configs")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: [String: Bool]]
        XCTAssertEqual(body?["tun"]?["enable"], false)
        let on = try FlClashController.request(config, method: "PATCH", enabled: true)
        let onBody = try JSONSerialization.jsonObject(with: XCTUnwrap(on.httpBody)) as? [String: [String: Bool]]
        XCTAssertEqual(onBody?["tun"]?["enable"], true)
        for address in ["http://example.com:9090", "http://127.0.0.1@evil.com",
                        "http://localhost:9090/path", "http://localhost:9090?x=1"] {
            XCTAssertThrowsError(try FlClashController.request(
                FlClashSettings(address: address, secret: ""), method: "GET"))
        }
    }

    func testDisableVerifiesStateAndRejectsFailures() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControllerStub.self]
        let controller = FlClashController(session: URLSession(configuration: configuration))
        try await controller.setTUN(false, configuration: FlClashSettings(address: "http://localhost:9090", secret: ""))
        try await controller.setTUN(true, configuration: FlClashSettings(address: "http://localhost:9090", secret: "still-on"))
        for secret in ["unauthorized", "still-on", "malformed"] {
            do {
                try await controller.setTUN(false, configuration: FlClashSettings(address: "http://localhost:9090", secret: secret))
                XCTFail("Must reject \(secret)")
            } catch {}
        }
    }

    func testOldSettingsRemainCompatibleAndNewSettingsRoundTrip() throws {
        let encoder = JSONEncoder()
        let old = try encoder.encode(AppSettings.default)
        XCTAssertNil(try JSONDecoder().decode(AppSettings.self, from: old).flClash)
        var settings = AppSettings.default
        settings.flClash = FlClashSettings(address: "http://localhost:9090", secret: "test")
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: encoder.encode(settings)), settings)
    }
}
