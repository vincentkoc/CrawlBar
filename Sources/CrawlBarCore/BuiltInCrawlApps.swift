import Foundation

public enum BuiltInCrawlApps {
    public static let gitcrawlID = CrawlAppID(rawValue: "gitcrawl")
    public static let slacrawlID = CrawlAppID(rawValue: "slacrawl")
    public static let discrawlID = CrawlAppID(rawValue: "discrawl")
    public static let notcrawlID = CrawlAppID(rawValue: "notcrawl")
    public static let gogcliID = CrawlAppID(rawValue: "gogcli")
    public static let wacliID = CrawlAppID(rawValue: "wacli")
    public static let birdclawID = CrawlAppID(rawValue: "birdclaw")
    public static let grainclawID = CrawlAppID(rawValue: "grainclaw")

    public static let all: [CrawlAppManifest] = [
        Self.gitcrawl,
        Self.slacrawl,
        Self.discrawl,
        Self.notcrawl,
        Self.gogcli,
        Self.wacli,
        Self.birdclaw,
        Self.grainclaw,
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
        privacy: .init(),
        configOptions: [
            .init(id: "github_token", label: "GitHub token", kind: .secret, help: "Token used for GitHub API refreshes.", placeholder: "ghp_...", envVar: "GITHUB_TOKEN", configKey: "github.token"),
            .init(id: "openai_api_key", label: "OpenAI API key", kind: .secret, help: "Used when Git Crawl generates embeddings.", placeholder: "sk-...", envVar: "OPENAI_API_KEY", configKey: "openai.api_key"),
            .init(id: "embedding_model", label: "Embedding model", kind: .choice, help: "Model used for local semantic indexing.", defaultValue: "text-embedding-3-small", choices: ["text-embedding-3-small", "text-embedding-3-large"], envVar: "OPENAI_EMBEDDING_MODEL", configKey: "embeddings.model"),
        ])

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
        privacy: .init(),
        configOptions: [
            .init(id: "slack_token", label: "Slack token", kind: .secret, help: "User or bot token for Slack API sync.", placeholder: "xoxp- or xoxb-", envVar: "SLACK_TOKEN", configKey: "slack.token"),
            .init(id: "openai_api_key", label: "OpenAI API key", kind: .secret, help: "Used when Slack Crawl generates embeddings.", placeholder: "sk-...", envVar: "OPENAI_API_KEY", configKey: "openai.api_key"),
            .init(id: "embedding_model", label: "Embedding model", kind: .choice, defaultValue: "text-embedding-3-small", choices: ["text-embedding-3-small", "text-embedding-3-large"], envVar: "OPENAI_EMBEDDING_MODEL", configKey: "embeddings.model"),
        ],
        install: .init(method: .homebrew, package: "vincentkoc/tap/slacrawl"))

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
        privacy: .init(containsPrivateMessages: true, exportsSecrets: false, localOnlyScopes: ["@me"]),
        configOptions: [
            .init(id: "discord_token", label: "Discord token", kind: .secret, help: "Token for Discord API or desktop-cache assisted sync.", placeholder: "token", envVar: "DISCORD_TOKEN", configKey: "discord.token"),
            .init(id: "openai_api_key", label: "OpenAI API key", kind: .secret, help: "Used when Discord Crawl generates embeddings.", placeholder: "sk-...", envVar: "OPENAI_API_KEY", configKey: "openai.api_key"),
            .init(id: "embedding_model", label: "Embedding model", kind: .choice, defaultValue: "text-embedding-3-small", choices: ["text-embedding-3-small", "text-embedding-3-large"], envVar: "OPENAI_EMBEDDING_MODEL", configKey: "embeddings.model"),
        ])

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
        privacy: .init(),
        configOptions: [
            .init(id: "notion_token", label: "Notion token", kind: .secret, help: "Token or session credential for Notion sync.", placeholder: "secret_...", envVar: "NOTION_TOKEN", configKey: "notion.token"),
            .init(id: "openai_api_key", label: "OpenAI API key", kind: .secret, help: "Used when Notion Crawl generates embeddings.", placeholder: "sk-...", envVar: "OPENAI_API_KEY", configKey: "openai.api_key"),
            .init(id: "embedding_model", label: "Embedding model", kind: .choice, defaultValue: "text-embedding-3-small", choices: ["text-embedding-3-small", "text-embedding-3-large"], envVar: "OPENAI_EMBEDDING_MODEL", configKey: "embeddings.model"),
        ],
        install: .init(method: .homebrew, package: "vincentkoc/tap/notcrawl"))

    public static let gogcli = CrawlAppManifest(
        id: Self.gogcliID,
        displayName: "Google",
        description: "Google account archive connector",
        availability: .comingSoon,
        binary: .init(name: "gogcli"),
        branding: .init(symbolName: "g.circle", accentColor: "#4285F4"),
        paths: .init(
            defaultConfig: "~/.config/gogcli/config.toml",
            configEnv: "GOGCLI_CONFIG",
            defaultDatabase: "~/.config/gogcli/gogcli.db",
            defaultCache: "~/.config/gogcli/cache",
            defaultLogs: "~/.config/gogcli/logs",
            defaultShare: "~/.config/gogcli/share"),
        commands: [:],
        capabilities: [],
        privacy: .init(exportsSecrets: false))

    public static let wacli = CrawlAppManifest(
        id: Self.wacliID,
        displayName: "WhatsApp",
        description: "WhatsApp message archive connector",
        availability: .comingSoon,
        binary: .init(name: "wacli"),
        branding: .init(symbolName: "message.circle", accentColor: "#25D366"),
        paths: .init(
            defaultConfig: "~/.config/wacli/config.toml",
            configEnv: "WACLI_CONFIG",
            defaultDatabase: "~/.config/wacli/wacli.db",
            defaultCache: "~/.config/wacli/cache",
            defaultLogs: "~/.config/wacli/logs",
            defaultShare: "~/.config/wacli/share"),
        commands: [:],
        capabilities: [],
        privacy: .init(containsPrivateMessages: true, exportsSecrets: false))

    public static let birdclaw = CrawlAppManifest(
        id: Self.birdclawID,
        displayName: "X",
        description: "X/Twitter account archive connector",
        availability: .comingSoon,
        binary: .init(name: "birdclaw"),
        branding: .init(symbolName: "xmark", accentColor: "#111111"),
        paths: .init(
            defaultConfig: "~/.config/birdclaw/config.toml",
            configEnv: "BIRDCLAW_CONFIG",
            defaultDatabase: "~/.config/birdclaw/birdclaw.db",
            defaultCache: "~/.config/birdclaw/cache",
            defaultLogs: "~/.config/birdclaw/logs",
            defaultShare: "~/.config/birdclaw/share"),
        commands: [:],
        capabilities: [],
        privacy: .init(exportsSecrets: false))

    public static let grainclaw = CrawlAppManifest(
        id: Self.grainclawID,
        displayName: "Granola",
        description: "Granola notes archive connector",
        availability: .comingSoon,
        binary: .init(name: "grainclaw"),
        branding: .init(symbolName: "waveform.and.magnifyingglass", accentColor: "#B56B45"),
        paths: .init(
            defaultConfig: "~/.config/grainclaw/config.toml",
            configEnv: "GRAINCLAW_CONFIG",
            defaultDatabase: "~/.config/grainclaw/grainclaw.db",
            defaultCache: "~/.config/grainclaw/cache",
            defaultLogs: "~/.config/grainclaw/logs",
            defaultShare: "~/.config/grainclaw/share"),
        commands: [:],
        capabilities: [],
        privacy: .init(containsPrivateMessages: true, exportsSecrets: false))
}
