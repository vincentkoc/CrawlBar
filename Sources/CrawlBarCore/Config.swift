import Foundation

public enum RefreshFrequency: String, Codable, CaseIterable, Sendable {
    case manual
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case hourly = "1h"

    public var seconds: TimeInterval? {
        switch self {
        case .manual:
            nil
        case .fiveMinutes:
            300
        case .fifteenMinutes:
            900
        case .thirtyMinutes:
            1_800
        case .hourly:
            3_600
        }
    }
}

public struct CrawlBarAppConfig: Codable, Equatable, Sendable, Identifiable {
    public var id: CrawlAppID
    public var enabled: Bool
    public var binaryPath: String?
    public var configPath: String?
    public var refreshFrequency: RefreshFrequency?
    public var preferredRefreshAction: String?
    public var autoRefreshEnabled: Bool
    public var shareEnabled: Bool
    public var shareAfterRefresh: Bool
    public var preferredShareAction: String?
    public var preferredUpdateAction: String?
    public var showInMenuBar: Bool
    public var configValues: [String: String]

    public init(
        id: CrawlAppID,
        enabled: Bool = true,
        binaryPath: String? = nil,
        configPath: String? = nil,
        refreshFrequency: RefreshFrequency? = nil,
        preferredRefreshAction: String? = "refresh",
        autoRefreshEnabled: Bool = false,
        shareEnabled: Bool = false,
        shareAfterRefresh: Bool = false,
        preferredShareAction: String? = "publish",
        preferredUpdateAction: String? = "update",
        showInMenuBar: Bool = true,
        configValues: [String: String] = [:])
    {
        self.id = id
        self.enabled = enabled
        self.binaryPath = binaryPath
        self.configPath = configPath
        self.refreshFrequency = refreshFrequency
        self.preferredRefreshAction = preferredRefreshAction
        self.autoRefreshEnabled = autoRefreshEnabled
        self.shareEnabled = shareEnabled
        self.shareAfterRefresh = shareAfterRefresh
        self.preferredShareAction = preferredShareAction
        self.preferredUpdateAction = preferredUpdateAction
        self.showInMenuBar = showInMenuBar
        self.configValues = configValues
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case binaryPath = "binary_path"
        case configPath = "config_path"
        case refreshFrequency = "refresh_frequency"
        case preferredRefreshAction = "preferred_refresh_action"
        case autoRefreshEnabled = "auto_refresh_enabled"
        case shareEnabled = "share_enabled"
        case shareAfterRefresh = "share_after_refresh"
        case preferredShareAction = "preferred_share_action"
        case preferredUpdateAction = "preferred_update_action"
        case showInMenuBar = "show_in_menu_bar"
        case configValues = "config_values"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(CrawlAppID.self, forKey: .id)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.binaryPath = try container.decodeIfPresent(String.self, forKey: .binaryPath)
        self.configPath = try container.decodeIfPresent(String.self, forKey: .configPath)
        self.refreshFrequency = try container.decodeIfPresent(RefreshFrequency.self, forKey: .refreshFrequency)
        self.preferredRefreshAction = try container.decodeIfPresent(String.self, forKey: .preferredRefreshAction) ?? "refresh"
        self.autoRefreshEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoRefreshEnabled) ?? false
        self.shareEnabled = try container.decodeIfPresent(Bool.self, forKey: .shareEnabled) ?? false
        self.shareAfterRefresh = try container.decodeIfPresent(Bool.self, forKey: .shareAfterRefresh) ?? false
        self.preferredShareAction = try container.decodeIfPresent(String.self, forKey: .preferredShareAction) ?? "publish"
        self.preferredUpdateAction = try container.decodeIfPresent(String.self, forKey: .preferredUpdateAction) ?? "update"
        self.showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        self.configValues = try container.decodeIfPresent([String: String].self, forKey: .configValues) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.enabled, forKey: .enabled)
        try container.encodeIfPresent(self.binaryPath, forKey: .binaryPath)
        try container.encodeIfPresent(self.configPath, forKey: .configPath)
        try container.encodeIfPresent(self.refreshFrequency, forKey: .refreshFrequency)
        try container.encodeIfPresent(self.preferredRefreshAction, forKey: .preferredRefreshAction)
        try container.encode(self.autoRefreshEnabled, forKey: .autoRefreshEnabled)
        try container.encode(self.shareEnabled, forKey: .shareEnabled)
        try container.encode(self.shareAfterRefresh, forKey: .shareAfterRefresh)
        try container.encodeIfPresent(self.preferredShareAction, forKey: .preferredShareAction)
        try container.encodeIfPresent(self.preferredUpdateAction, forKey: .preferredUpdateAction)
        try container.encode(self.showInMenuBar, forKey: .showInMenuBar)
        if !self.configValues.isEmpty {
            try container.encode(self.configValues, forKey: .configValues)
        }
    }
}

public struct CrawlBarConfig: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var refreshFrequency: RefreshFrequency
    public var manifestDirectories: [String]
    public var apps: [CrawlBarAppConfig]

    public init(
        version: Int = Self.currentVersion,
        refreshFrequency: RefreshFrequency = .fifteenMinutes,
        manifestDirectories: [String] = ["~/.crawlbar/apps"],
        apps: [CrawlBarAppConfig] = [])
    {
        self.version = version
        self.refreshFrequency = refreshFrequency
        self.manifestDirectories = manifestDirectories
        self.apps = apps
    }

    public func normalized(knownIDs: [CrawlAppID] = BuiltInCrawlApps.all.map(\.id)) -> CrawlBarConfig {
        var seen: Set<CrawlAppID> = []
        var normalizedApps: [CrawlBarAppConfig] = []
        for app in self.apps where !seen.contains(app.id) {
            seen.insert(app.id)
            normalizedApps.append(app)
        }
        for id in knownIDs where !seen.contains(id) {
            normalizedApps.append(CrawlBarAppConfig(id: id, enabled: true))
        }
        return CrawlBarConfig(
            version: Self.currentVersion,
            refreshFrequency: self.refreshFrequency,
            manifestDirectories: self.manifestDirectories.isEmpty ? ["~/.crawlbar/apps"] : self.manifestDirectories,
            apps: normalizedApps)
    }

    public func appConfig(for id: CrawlAppID) -> CrawlBarAppConfig? {
        self.apps.first { $0.id == id }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case refreshFrequency = "refresh_frequency"
        case manifestDirectories = "manifest_directories"
        case apps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        self.refreshFrequency = try container.decodeIfPresent(RefreshFrequency.self, forKey: .refreshFrequency) ?? .fifteenMinutes
        self.manifestDirectories = try container.decodeIfPresent([String].self, forKey: .manifestDirectories) ?? ["~/.crawlbar/apps"]
        self.apps = try container.decodeIfPresent([CrawlBarAppConfig].self, forKey: .apps) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.version, forKey: .version)
        try container.encode(self.refreshFrequency, forKey: .refreshFrequency)
        try container.encode(self.manifestDirectories, forKey: .manifestDirectories)
        try container.encode(self.apps, forKey: .apps)
    }
}

public enum CrawlBarConfigStoreError: LocalizedError {
    case decodeFailed(String)
    case encodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .decodeFailed(details):
            "Failed to decode CrawlBar config: \(details)"
        case let .encodeFailed(details):
            "Failed to encode CrawlBar config: \(details)"
        }
    }
}

public struct CrawlBarConfigStore: @unchecked Sendable {
    public var fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL = Self.defaultURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> CrawlBarConfig? {
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return nil }
        let data = try Data(contentsOf: self.fileURL)
        do {
            return try CrawlCoding.makeJSONDecoder().decode(CrawlBarConfig.self, from: data).normalized()
        } catch {
            throw CrawlBarConfigStoreError.decodeFailed(error.localizedDescription)
        }
    }

    public func loadOrCreateDefault() throws -> CrawlBarConfig {
        if let existing = try self.load() {
            return existing
        }
        let config = CrawlBarConfig().normalized()
        try self.save(config)
        return config
    }

    public func save(_ config: CrawlBarConfig) throws {
        let normalized = config.normalized()
        let data: Data
        do {
            data = try CrawlCoding.makeJSONEncoder().encode(normalized)
        } catch {
            throw CrawlBarConfigStoreError.encodeFailed(error.localizedDescription)
        }
        let directory = self.fileURL.deletingLastPathComponent()
        if !self.fileManager.fileExists(atPath: directory.path) {
            try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: self.fileURL, options: [.atomic])
        #if os(macOS) || os(Linux)
        try self.fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: self.fileURL.path)
        #endif
    }

    public static func defaultURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".crawlbar", isDirectory: true)
            .appendingPathComponent("config.json")
    }
}

public enum PathExpander {
    public static func expandHome(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: home).appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
    }
}
