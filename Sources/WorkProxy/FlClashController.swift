import Foundation
import WorkProxyCore

enum FlClashControlError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

struct FlClashController {
    let session: URLSession

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        self.session = session ?? URLSession(configuration: configuration, delegate: LocalControllerDelegate(), delegateQueue: nil)
    }

    static func request(_ configuration: FlClashSettings, method: String, enabled: Bool = false) throws -> URLRequest {
        guard let url = URL(string: configuration.address),
              url.scheme == "http",
              ["127.0.0.1", "localhost", "[::1]", "::1"].contains(url.host ?? ""),
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              (1...65535).contains(url.port ?? 80),
              !configuration.secret.contains(where: { $0.isNewline }) else {
            throw FlClashControlError.message("控制器地址需为本机 HTTP 地址，例如 http://127.0.0.1:9090；密钥不能含换行。")
        }
        var request = URLRequest(url: url.appendingPathComponent("configs"))
        request.httpMethod = method
        request.timeoutInterval = 5
        if !configuration.secret.isEmpty {
            request.setValue("Bearer \(configuration.secret)", forHTTPHeaderField: "Authorization")
        }
        if method == "PATCH" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["tun": ["enable": enabled]])
        }
        return request
    }

    func tunEnabled(_ configuration: FlClashSettings) async throws -> Bool {
        let data = try await send(Self.request(configuration, method: "GET"))
        struct Config: Decodable {
            struct Tun: Decodable { let enable: Bool }
            let tun: Tun
        }
        return try JSONDecoder().decode(Config.self, from: data).tun.enable
    }

    func setTUN(_ enabled: Bool, configuration: FlClashSettings) async throws {
        _ = try await send(Self.request(configuration, method: "PATCH", enabled: enabled))
        guard try await tunEnabled(configuration) == enabled else {
            throw FlClashControlError.message("TUN 状态与请求不一致。")
        }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw FlClashControlError.message("控制器响应无效。")
        }
        guard (200...299).contains(response.statusCode) else {
            throw FlClashControlError.message("控制器返回 HTTP \(response.statusCode)，请检查控制器和密钥。")
        }
        return data
    }
}

private final class LocalControllerDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
