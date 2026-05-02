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
    public enum Availability: String, Codable, Equatable, Sendable {
        case available
        case comingSoon = "coming_soon"
    }

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

    public enum InstallMethod: String, Codable, Equatable, Sendable {
        case homebrew
    }

    public struct Install: Codable, Equatable, Sendable {
        public var method: InstallMethod
        public var package: String

        public init(method: InstallMethod, package: String) {
            self.method = method
            self.package = package
        }
    }

    public enum ConfigOptionKind: String, Codable, Equatable, Sendable {
        case string
        case secret
        case boolean
        case choice
    }

    public struct ConfigOption: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var label: String
        public var kind: ConfigOptionKind
        public var help: String?
        public var placeholder: String?
        public var defaultValue: String?
        public var choices: [String]
        public var envVar: String?
        public var configKey: String?

        public init(
            id: String,
            label: String,
            kind: ConfigOptionKind = .string,
            help: String? = nil,
            placeholder: String? = nil,
            defaultValue: String? = nil,
            choices: [String] = [],
            envVar: String? = nil,
            configKey: String? = nil)
        {
            self.id = id
            self.label = label
            self.kind = kind
            self.help = help
            self.placeholder = placeholder
            self.defaultValue = defaultValue
            self.choices = choices
            self.envVar = envVar
            self.configKey = configKey
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case label
            case kind
            case help
            case placeholder
            case defaultValue = "default_value"
            case choices
            case envVar = "env_var"
            case configKey = "config_key"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(String.self, forKey: .id)
            self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? self.id
            self.kind = try container.decodeIfPresent(ConfigOptionKind.self, forKey: .kind) ?? .string
            self.help = try container.decodeIfPresent(String.self, forKey: .help)
            self.placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
            self.defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
            self.choices = try container.decodeIfPresent([String].self, forKey: .choices) ?? []
            self.envVar = try container.decodeIfPresent(String.self, forKey: .envVar)
            self.configKey = try container.decodeIfPresent(String.self, forKey: .configKey)
        }
    }

    public var schemaVersion: Int
    public var id: CrawlAppID
    public var displayName: String
    public var description: String
    public var availability: Availability
    public var binary: Binary
    public var branding: Branding
    public var paths: Paths
    public var commands: [String: [String]]
    public var capabilities: [CrawlAppCapability]
    public var privacy: Privacy
    public var configOptions: [ConfigOption]
    public var install: Install?

    public init(
        schemaVersion: Int = 1,
        id: CrawlAppID,
        displayName: String,
        description: String,
        availability: Availability = .available,
        binary: Binary,
        branding: Branding,
        paths: Paths,
        commands: [String: [String]],
        capabilities: [CrawlAppCapability],
        privacy: Privacy = Privacy(),
        configOptions: [ConfigOption] = [],
        install: Install? = nil)
    {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.description = description
        self.availability = availability
        self.binary = binary
        self.branding = branding
        self.paths = paths
        self.commands = commands
        self.capabilities = capabilities
        self.privacy = privacy
        self.configOptions = configOptions
        self.install = install
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id
        case displayName = "display_name"
        case description
        case availability
        case binary
        case branding
        case paths
        case commands
        case capabilities
        case privacy
        case configOptions = "config_options"
        case install
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.id = try container.decode(CrawlAppID.self, forKey: .id)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.description = try container.decode(String.self, forKey: .description)
        self.availability = try container.decodeIfPresent(Availability.self, forKey: .availability) ?? .available
        self.binary = try container.decode(Binary.self, forKey: .binary)
        self.branding = try container.decode(Branding.self, forKey: .branding)
        self.paths = try container.decode(Paths.self, forKey: .paths)
        self.commands = try container.decode([String: [String]].self, forKey: .commands)
        self.capabilities = try container.decode([CrawlAppCapability].self, forKey: .capabilities)
        self.privacy = try container.decodeIfPresent(Privacy.self, forKey: .privacy) ?? Privacy()
        self.configOptions = try container.decodeIfPresent([ConfigOption].self, forKey: .configOptions) ?? []
        self.install = try container.decodeIfPresent(Install.self, forKey: .install)
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
    public var configValues: [String: String]
    public var enabled: Bool

    public var id: CrawlAppID {
        self.manifest.id
    }

    public init(
        manifest: CrawlAppManifest,
        binaryPath: String? = nil,
        configPathOverride: String? = nil,
        configValues: [String: String] = [:],
        enabled: Bool = true)
    {
        self.manifest = manifest
        self.binaryPath = binaryPath
        self.configPathOverride = configPathOverride
        self.configValues = configValues
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
