import Foundation

public struct CrawlAppID: RawRepresentable, Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        self.rawValue
    }

    public static func < (lhs: CrawlAppID, rhs: CrawlAppID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct CrawlAppManifest: Codable, Equatable, Sendable, Identifiable {
    public struct Binary: Codable, Equatable, Sendable {
        public var name: String
        public var minVersion: String?

        public init(name: String, minVersion: String? = nil) {
            self.name = name
            self.minVersion = minVersion
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case minVersion = "min_version"
        }
    }

    public struct Branding: Codable, Equatable, Sendable {
        public var symbolName: String
        public var accentColor: String
        public var iconPath: String?
        public var bundleIdentifier: String?

        public init(
            symbolName: String,
            accentColor: String,
            iconPath: String? = nil,
            bundleIdentifier: String? = nil)
        {
            self.symbolName = symbolName
            self.accentColor = accentColor
            self.iconPath = iconPath
            self.bundleIdentifier = bundleIdentifier
        }

        private enum CodingKeys: String, CodingKey {
            case symbolName = "symbol_name"
            case accentColor = "accent_color"
            case iconPath = "icon_path"
            case bundleIdentifier = "bundle_identifier"
        }
    }

    public struct Paths: Codable, Equatable, Sendable {
        public var defaultConfig: String?
        public var configEnv: String?
        public var defaultDatabase: String?
        public var defaultCache: String?
        public var defaultLogs: String?
        public var defaultShare: String?

        public init(
            defaultConfig: String? = nil,
            configEnv: String? = nil,
            defaultDatabase: String? = nil,
            defaultCache: String? = nil,
            defaultLogs: String? = nil,
            defaultShare: String? = nil)
        {
            self.defaultConfig = defaultConfig
            self.configEnv = configEnv
            self.defaultDatabase = defaultDatabase
            self.defaultCache = defaultCache
            self.defaultLogs = defaultLogs
            self.defaultShare = defaultShare
        }

        private enum CodingKeys: String, CodingKey {
            case defaultConfig = "default_config"
            case configEnv = "config_env"
            case defaultDatabase = "default_database"
            case defaultCache = "default_cache"
            case defaultLogs = "default_logs"
            case defaultShare = "default_share"
        }
    }

    public struct Privacy: Codable, Equatable, Sendable {
        public var containsPrivateMessages: Bool
        public var exportsSecrets: Bool
        public var localOnlyScopes: [String]

        public init(
            containsPrivateMessages: Bool = false,
            exportsSecrets: Bool = false,
            localOnlyScopes: [String] = [])
        {
            self.containsPrivateMessages = containsPrivateMessages
            self.exportsSecrets = exportsSecrets
            self.localOnlyScopes = localOnlyScopes
        }

        private enum CodingKeys: String, CodingKey {
            case containsPrivateMessages = "contains_private_messages"
            case exportsSecrets = "exports_secrets"
            case localOnlyScopes = "local_only_scopes"
        }
    }

    public var schemaVersion: Int
    public var id: CrawlAppID
    public var displayName: String
    public var description: String
    public var binary: Binary
    public var branding: Branding
    public var paths: Paths
    public var commands: [String: [String]]
    public var capabilities: [CrawlAppCapability]
    public var privacy: Privacy

    public init(
        schemaVersion: Int = 1,
        id: CrawlAppID,
        displayName: String,
        description: String,
        binary: Binary,
        branding: Branding,
        paths: Paths,
        commands: [String: [String]],
        capabilities: [CrawlAppCapability],
        privacy: Privacy = Privacy())
    {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.description = description
        self.binary = binary
        self.branding = branding
        self.paths = paths
        self.commands = commands
        self.capabilities = capabilities
        self.privacy = privacy
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id
        case displayName = "display_name"
        case description
        case binary
        case branding
        case paths
        case commands
        case capabilities
        case privacy
    }
}

public enum CrawlAppCapability: String, Codable, Equatable, Sendable, CaseIterable {
    case status
    case doctor
    case refresh
    case search
    case publish
    case subscribe
    case update
    case desktopCache = "desktop_cache"
    case exportMarkdown = "export_markdown"
    case exportDatabase = "export_database"
    case maintain
}

public enum CrawlAppState: String, Codable, Equatable, Sendable {
    case current
    case stale
    case syncing
    case needsConfig = "needs_config"
    case needsAuth = "needs_auth"
    case error
    case disabled
    case unknown
}

public struct CrawlCount: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var value: Int

    public init(id: String, label: String, value: Int) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct CrawlFreshness: Codable, Equatable, Sendable {
    public var status: CrawlAppState
    public var ageSeconds: Int?
    public var staleAfterSeconds: Int?

    public init(status: CrawlAppState, ageSeconds: Int? = nil, staleAfterSeconds: Int? = nil) {
        self.status = status
        self.ageSeconds = ageSeconds
        self.staleAfterSeconds = staleAfterSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case ageSeconds = "age_seconds"
        case staleAfterSeconds = "stale_after_seconds"
    }
}

public struct CrawlShareStatus: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var repoPath: String?
    public var remote: String?
    public var branch: String?
    public var needsUpdate: Bool?

    public init(enabled: Bool, repoPath: String? = nil, remote: String? = nil, branch: String? = nil, needsUpdate: Bool? = nil) {
        self.enabled = enabled
        self.repoPath = repoPath
        self.remote = remote
        self.branch = branch
        self.needsUpdate = needsUpdate
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case repoPath = "repo_path"
        case remote
        case branch
        case needsUpdate = "needs_update"
    }
}

public enum CrawlDatabaseKind: String, Codable, Equatable, Sendable {
    case sqlite
    case cache
    case logical
}

public struct CrawlDatabaseResource: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var kind: CrawlDatabaseKind
    public var role: String?
    public var path: String?
    public var isPrimary: Bool
    public var bytes: Int?
    public var modifiedAt: Date?
    public var counts: [CrawlCount]

    public init(
        id: String,
        label: String,
        kind: CrawlDatabaseKind,
        role: String? = nil,
        path: String? = nil,
        isPrimary: Bool = false,
        bytes: Int? = nil,
        modifiedAt: Date? = nil,
        counts: [CrawlCount] = [])
    {
        self.id = id
        self.label = label
        self.kind = kind
        self.role = role
        self.path = path
        self.isPrimary = isPrimary
        self.bytes = bytes
        self.modifiedAt = modifiedAt
        self.counts = counts
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case kind
        case role
        case path
        case isPrimary = "is_primary"
        case bytes
        case modifiedAt = "modified_at"
        case counts
    }
}

public struct CrawlAppStatus: Codable, Equatable, Sendable, Identifiable {
    public var schemaVersion: Int
    public var appID: CrawlAppID
    public var generatedAt: Date
    public var state: CrawlAppState
    public var summary: String
    public var configPath: String?
    public var databasePath: String?
    public var databaseBytes: Int?
    public var walBytes: Int?
    public var lastSyncAt: Date?
    public var lastImportAt: Date?
    public var lastExportAt: Date?
    public var counts: [CrawlCount]
    public var databases: [CrawlDatabaseResource]
    public var freshness: CrawlFreshness?
    public var share: CrawlShareStatus?
    public var warnings: [String]
    public var errors: [String]

    public var id: CrawlAppID {
        self.appID
    }

    public init(
        schemaVersion: Int = 1,
        appID: CrawlAppID,
        generatedAt: Date = Date(),
        state: CrawlAppState,
        summary: String,
        configPath: String? = nil,
        databasePath: String? = nil,
        databaseBytes: Int? = nil,
        walBytes: Int? = nil,
        lastSyncAt: Date? = nil,
        lastImportAt: Date? = nil,
        lastExportAt: Date? = nil,
        counts: [CrawlCount] = [],
        databases: [CrawlDatabaseResource] = [],
        freshness: CrawlFreshness? = nil,
        share: CrawlShareStatus? = nil,
        warnings: [String] = [],
        errors: [String] = [])
    {
        self.schemaVersion = schemaVersion
        self.appID = appID
        self.generatedAt = generatedAt
        self.state = state
        self.summary = summary
        self.configPath = configPath
        self.databasePath = databasePath
        self.databaseBytes = databaseBytes
        self.walBytes = walBytes
        self.lastSyncAt = lastSyncAt
        self.lastImportAt = lastImportAt
        self.lastExportAt = lastExportAt
        self.counts = counts
        self.databases = databases
        self.freshness = freshness
        self.share = share
        self.warnings = warnings
        self.errors = errors
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case appID = "app_id"
        case generatedAt = "generated_at"
        case state
        case summary
        case configPath = "config_path"
        case databasePath = "database_path"
        case databaseBytes = "database_bytes"
        case walBytes = "wal_bytes"
        case lastSyncAt = "last_sync_at"
        case lastImportAt = "last_import_at"
        case lastExportAt = "last_export_at"
        case counts
        case databases
        case freshness
        case share
        case warnings
        case errors
    }
}

public struct CrawlAppInstallation: Codable, Equatable, Sendable, Identifiable {
    public var manifest: CrawlAppManifest
    public var binaryPath: String?
    public var configPathOverride: String?
    public var enabled: Bool

    public var id: CrawlAppID {
        self.manifest.id
    }

    public init(
        manifest: CrawlAppManifest,
        binaryPath: String? = nil,
        configPathOverride: String? = nil,
        enabled: Bool = true)
    {
        self.manifest = manifest
        self.binaryPath = binaryPath
        self.configPathOverride = configPathOverride
        self.enabled = enabled
    }
}

public enum CrawlActionID: String, Codable, Hashable, Sendable {
    case status
    case doctor
    case refresh
    case publish
    case update
    case desktopCacheImport = "desktop-cache-import"
    case exportMarkdown = "export-md"
}

public struct CrawlCommandResult: Codable, Equatable, Sendable {
    public var appID: CrawlAppID
    public var action: String
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var startedAt: Date
    public var finishedAt: Date

    public var succeeded: Bool {
        self.exitCode == 0
    }

    public init(
        appID: CrawlAppID,
        action: String,
        exitCode: Int32,
        stdout: String,
        stderr: String,
        startedAt: Date,
        finishedAt: Date)
    {
        self.appID = appID
        self.action = action
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
