import CrawlBarCore
import Foundation

@main
enum CrawlBarSelfTest {
    static func main() throws {
        try Self.testAppIDSortsByRawValue()
        try Self.testDefaultConfigNormalizesBuiltInApps()
        try Self.testConfigStoreRoundTrips()
        try Self.testExternalManifestCatalog()
        try Self.testStatusMapperNormalizesCounts()
        try Self.testRedactorScrubsSecrets()
        print("crawlbar selftest ok")
    }

    private static func testAppIDSortsByRawValue() throws {
        try Self.expect(
            [CrawlAppID(rawValue: "b"), CrawlAppID(rawValue: "a")].sorted().map(\.rawValue) == ["a", "b"],
            "app ids sort by raw value")
    }

    private static func testDefaultConfigNormalizesBuiltInApps() throws {
        let config = CrawlBarConfig(apps: []).normalized()
        try Self.expect(config.version == CrawlBarConfig.currentVersion, "config version normalizes")
        try Self.expect(config.apps.map(\.id) == BuiltInCrawlApps.all.map(\.id), "built-in apps are present")
        try Self.expect(config.manifestDirectories == ["~/.crawlbar/apps"], "manifest directory default is present")
    }

    private static func testConfigStoreRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("config.json")
        let store = CrawlBarConfigStore(fileURL: url)
        let config = CrawlBarConfig(
            refreshFrequency: .hourly,
            apps: [CrawlBarAppConfig(
                id: BuiltInCrawlApps.gitcrawlID,
                enabled: false,
                configValues: ["embedding_model": "text-embedding-3-large"])])

        try store.save(config)
        guard let loaded = try store.load() else {
            throw SelfTestError.failed("config loads after save")
        }

        try Self.expect(loaded.refreshFrequency == .hourly, "refresh frequency round trips")
        try Self.expect(loaded.appConfig(for: BuiltInCrawlApps.gitcrawlID)?.enabled == false, "app enablement round trips")
        try Self.expect(loaded.appConfig(for: BuiltInCrawlApps.gitcrawlID)?.configValues["embedding_model"] == "text-embedding-3-large", "app config values round trip")
        try Self.expect(loaded.apps.count == BuiltInCrawlApps.all.count, "config store normalizes built-ins")
    }

    private static func testExternalManifestCatalog() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = CrawlAppManifest(
            id: CrawlAppID(rawValue: "customcrawl"),
            displayName: "Custom Crawl",
            description: "A custom crawl app",
            binary: .init(name: "customcrawl"),
            branding: .init(symbolName: "square.grid.2x2", accentColor: "#123456"),
            paths: .init(defaultConfig: "~/.customcrawl/config.toml"),
            commands: ["status": ["status", "--json"]],
            capabilities: [.status])
        let data = try CrawlCoding.makeJSONEncoder().encode(manifest)
        try data.write(to: directory.appendingPathComponent("customcrawl.json"))

        let config = CrawlBarConfig(manifestDirectories: [directory.path])
        let manifests = CrawlManifestCatalog().manifests(config: config)
        try Self.expect(manifests.contains { $0.id == manifest.id }, "external manifests load from disk")
        try Self.expect(BuiltInCrawlApps.gitcrawl.configOptions.contains { $0.id == "embedding_model" }, "built-in config options exist")
        try Self.expect(BuiltInCrawlApps.slacrawl.install?.package == "vincentkoc/tap/slacrawl", "built-in install metadata exists")
    }

    private static func testStatusMapperNormalizesCounts() throws {
        let output = """
        {"message_count":42,"channel_count":3,"last_sync_at":"2026-05-01T12:00:00Z","db_path":"/tmp/discrawl.db"}
        """
        let result = CrawlCommandResult(
            appID: BuiltInCrawlApps.discrawlID,
            action: "status",
            exitCode: 0,
            stdout: output,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())

        let status = CrawlStatusMapper().status(from: result, manifest: BuiltInCrawlApps.discrawl)
        try Self.expect(status.counts.contains(CrawlCount(id: "messages", label: "Messages", value: 42)), "discrawl messages map")
        try Self.expect(status.databasePath == "/tmp/discrawl.db", "database path maps")
        try Self.expect(status.databases.first?.label == "Discord archive", "database inventory maps")
        try Self.expect(status.databases.first?.counts.contains(CrawlCount(id: "messages", label: "Messages", value: 42)) == true, "database inventory carries counts")
    }

    private static func testRedactorScrubsSecrets() throws {
        let redacted = CrawlCommandRedactor().redact("token=abc123\nAuthorization: Bearer secret-token")
        try Self.expect(!redacted.contains("abc123"), "token value redacts")
        try Self.expect(!redacted.contains("secret-token"), "bearer value redacts")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw SelfTestError.failed(message)
        }
    }
}

private enum SelfTestError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message):
            "selftest failed: \(message)"
        }
    }
}
