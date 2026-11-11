import Foundation

public protocol SettingsStoring: Sendable {
    func load() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}

/// 以 JSON 文件保存设置。损坏文件会被改名隔离，避免每次启动重复解析失败。
public struct JSONSettingsStore: SettingsStoring, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("workProxy", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    public func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .default
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            quarantineCorruptFile()
            return .default
        }
    }

    public func save(_ settings: AppSettings) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
        // 配置包含 SSID 与地点坐标，只允许当前用户读取。
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: url.path)
    }

    /// 把无法解码的文件移到同目录的带时间戳名称下。尽力而为，失败不抛出。
    private func quarantineCorruptFile() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("settings.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: backup)
    }
}

/// 线程安全的内存实现，供测试与预览使用。
public final class InMemorySettingsStore: SettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: AppSettings
    private var saves: [AppSettings] = []

    public init(_ settings: AppSettings = .default) {
        self.settings = settings
    }

    public func load() throws -> AppSettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        lock.lock()
        defer { lock.unlock() }
        self.settings = settings
        saves.append(settings)
    }

    public var savedSettings: [AppSettings] {
        lock.lock()
        defer { lock.unlock() }
        return saves
    }

    public var saveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return saves.count
    }
}
