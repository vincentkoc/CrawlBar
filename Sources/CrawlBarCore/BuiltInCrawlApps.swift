import Foundation

public enum BuiltInCrawlApps {
    public static let gitcrawlID = CrawlAppID(rawValue: "gitcrawl")
    public static let slacrawlID = CrawlAppID(rawValue: "slacrawl")
    public static let discrawlID = CrawlAppID(rawValue: "discrawl")
    public static let notcrawlID = CrawlAppID(rawValue: "notcrawl")

    public static let all: [CrawlAppManifest] = [
        Self.gitcrawl,
        Self.slacrawl,
        Self.discrawl,
        Self.notcrawl,
    ]

    public static func manifest(for id: CrawlAppID) -> CrawlAppManifest? {
        self.all.first { $0.id == id }
    }

    public static let gitcrawl = CrawlAppManifest(
        id: Self.gitcrawlID,
        displayName: "GitHub",
        description: "Local GitHub issue and pull request archive",
        binary: .init(name: "gitcrawl"),
        branding: .init(
            symbolName: "point.3.connected.trianglepath.dotted",
            accentColor: "#24292F",
            bundleIdentifier: "com.github.GitHubClient"),
        paths: .init(
            defaultConfig: "~/.config/gitcrawl/config.toml",
            configEnv: "GITCRAWL_CONFIG",
            defaultDatabase: "~/.config/gitcrawl/gitcrawl.db",
            defaultCache: "~/.config/gitcrawl/cache",
            defaultLogs: "~/.config/gitcrawl/logs",
            defaultShare: "~/.config/gitcrawl/share"),
        commands: [
            "metadata": ["metadata", "--json"],
            "status": ["--json", "doctor"],
            "doctor": ["--json", "doctor"],
            "refresh": ["refresh"],
        ],
        capabilities: [.status, .doctor, .refresh, .search],
        privacy: .init())

    public static let slacrawl = CrawlAppManifest(
        id: Self.slacrawlID,
        displayName: "Slack",
        description: "Local-first Slack workspace archive",
        binary: .init(name: "slacrawl"),
        branding: .init(
            symbolName: "bubble.left.and.bubble.right",
            accentColor: "#4A154B",
            bundleIdentifier: "com.tinyspeck.slackmacgap"),
        paths: .init(
            defaultConfig: "~/.slacrawl/config.toml",
            configEnv: "SLACRAWL_CONFIG",
            defaultDatabase: "~/.slacrawl/slacrawl.db",
            defaultCache: "~/.slacrawl/cache",
            defaultLogs: "~/.slacrawl/logs",
            defaultShare: "~/.slacrawl/share"),
        commands: [
            "metadata": ["metadata", "--json"],
            "status": ["--format", "json", "status"],
            "doctor": ["--format", "json", "doctor"],
            "refresh": ["--format", "json", "sync", "--source", "api", "--latest-only"],
            "publish": ["--format", "json", "publish"],
            "update": ["--format", "json", "update"],
        ],
        capabilities: [.status, .doctor, .refresh, .search, .publish, .subscribe, .update, .desktopCache],
        privacy: .init())

    public static let discrawl = CrawlAppManifest(
        id: Self.discrawlID,
        displayName: "Discord",
        description: "Local Discord guild and desktop-cache archive",
        binary: .init(name: "discrawl"),
        branding: .init(
            symbolName: "antenna.radiowaves.left.and.right",
            accentColor: "#5865F2",
            bundleIdentifier: "com.hnc.Discord"),
        paths: .init(
            defaultConfig: "~/.discrawl/config.toml",
            configEnv: "DISCRAWL_CONFIG",
            defaultDatabase: "~/.discrawl/discrawl.db",
            defaultCache: "~/.discrawl/cache",
            defaultLogs: "~/.discrawl/logs",
            defaultShare: "~/.discrawl/share"),
        commands: [
            "metadata": ["metadata", "--json"],
            "status": ["--json", "status"],
            "doctor": ["--json", "doctor"],
            "refresh": ["--json", "sync", "--source", "both"],
            "desktop-cache-import": ["--json", "sync", "--source", "wiretap"],
            "publish": ["--json", "publish"],
            "update": ["--json", "update"],
        ],
        capabilities: [.status, .doctor, .refresh, .search, .publish, .subscribe, .update, .desktopCache],
        privacy: .init(containsPrivateMessages: true, exportsSecrets: false, localOnlyScopes: ["@me"]))

    public static let notcrawl = CrawlAppManifest(
        id: Self.notcrawlID,
        displayName: "Notion",
        description: "Local Notion archive with Markdown and table exports",
        binary: .init(name: "notcrawl"),
        branding: .init(
            symbolName: "doc.text.magnifyingglass",
            accentColor: "#111111",
            bundleIdentifier: "notion.id"),
        paths: .init(
            defaultConfig: "~/.notcrawl/config.toml",
            configEnv: "NOTCRAWL_CONFIG",
            defaultDatabase: "~/.notcrawl/notcrawl.db",
            defaultCache: "~/.notcrawl/cache",
            defaultLogs: "~/.notcrawl/logs",
            defaultShare: "~/.notcrawl/share"),
        commands: [
            "metadata": ["metadata", "--json"],
            "status": ["status"],
            "doctor": ["doctor"],
            "refresh": ["sync", "--source", "desktop"],
            "export-md": ["export-md"],
            "publish": ["publish"],
            "update": ["update"],
        ],
        capabilities: [.status, .doctor, .refresh, .search, .publish, .subscribe, .update, .exportMarkdown, .exportDatabase, .maintain],
        privacy: .init())
}
