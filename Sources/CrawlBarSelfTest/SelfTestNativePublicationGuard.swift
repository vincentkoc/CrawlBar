import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func testNativePublicationGuard() throws {
        for change in ["unchanged", "changed", "same-mtime", "secret-only", "missing", "invalid-utf8"] {
            let fixture = try NativePublicationFixture(change: change)
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let coordinator = CrawlActionCoordinator()
            let baseline = fixture.registry.appConfigWithNativeValues(fixture.app, manifest: fixture.manifest, includeSecrets: false)
            let permit = fixture.registry.nativePublicationGuard(for: fixture.installation, configValues: fixture.values, runner: fixture.runner)
            let outcome = try coordinator.run(
                installation: fixture.installation, config: baseline, configValues: fixture.values, action: "pull",
                allowShare: {
                    fixture.registry.matchesPersistedAppConfig(baseline, manifest: fixture.manifest) && permit()
                })
            { action in
                let result = try fixture.runner.run(
                    installation: fixture.installation, configValues: fixture.values, action: action, timeoutSeconds: 5)
                if action == "pull", change == "same-mtime" {
                    try FileManager.default.setAttributes([.modificationDate: fixture.modificationDate], ofItemAtPath: fixture.nativeURL.path)
                    try Self.expect(try fixture.nativeModificationDate() == fixture.modificationDate, "native overwrite restores the exact primed mtime")
                }
                return result
            }
            let publish = change == "unchanged" || change == "secret-only"
            try Self.expect(outcome.failure == nil, "native publication fixture \(change) has no action error")
            try Self.expect(outcome.results.map(\.action) == (publish ? ["pull", "share"] : ["pull"]), "native publication phases \(change)")
            try Self.expect(try fixture.marker("sync") == "sync\n", "real sync ran exactly once for \(change)")
            try Self.expect(try fixture.marker("publish") == (publish ? "A\n" : ""), "real publisher invocation for \(change)")
            if !publish {
                try Self.expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("publish.marker").path), "denied publisher created no marker")
            }
            try fixture.expectMainUnchanged()
            if change == "missing" {
                try Self.expect(!FileManager.default.fileExists(atPath: fixture.nativeURL.path), "missing native config is not recreated")
            } else {
                let native = try Data(contentsOf: fixture.nativeURL)
                let expected = change == "unchanged" ? fixture.initialNative : fixture.nextNative
                try Self.expect(native == expected, "guard preserves exact native bytes for \(change)")
                if change == "same-mtime" {
                    try Self.expect(native != fixture.initialNative, "same-mtime fixture changed native bytes")
                    try Self.expect(try fixture.nativeModificationDate() == fixture.modificationDate, "guard preserves native mtime")
                }
            }
            if change == "changed" {
                let current = try fixture.nativeStore.read(path: fixture.nativeURL.path, manifest: fixture.manifest)
                try Self.expect(current["destination"] == "B" && fixture.values == ["destination": "A"], "persisted A cannot mask native B")
                try Self.expect(!permit(), "changed native state is denied before standalone control")
                var guardCalls = 0
                let standalone = try coordinator.run(
                    installation: fixture.installation, config: baseline, configValues: fixture.values, action: "share",
                    allowShare: {
                        guardCalls += 1
                        return permit()
                    })
                { action in
                    try fixture.runner.run(
                        installation: fixture.installation, configValues: fixture.values, action: action, timeoutSeconds: 5)
                }
                try Self.expect(standalone.failure == nil && standalone.results.map(\.action) == ["share"], "standalone share still runs")
                try Self.expect(guardCalls == 0 && (try fixture.marker("publish")) == "B\n", "standalone share bypasses the between-phase hook")
            }
        }
        try Self.testNativePublicationRetry()
        try Self.testNativePublicationMissingValues()
        try Self.testNativeConfigEnvironment()
    }

    private static func testNativePublicationRetry() throws {
        let fixture = try NativePublicationFixture(change: "retry")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let coordinator = CrawlActionCoordinator()
        let now = Date()
        let permit = fixture.registry.nativePublicationGuard(for: fixture.installation, configValues: fixture.values, runner: fixture.runner)
        let first = try coordinator.run(
            installation: fixture.installation, config: fixture.app, configValues: fixture.values, action: "pull", now: now,
            allowShare: {
                fixture.registry.matchesPersistedRawAppConfig(fixture.app) && permit()
            })
        { action in
            try fixture.runner.run(
                installation: fixture.installation, configValues: fixture.values, action: action, timeoutSeconds: 5)
        }
        try Self.expect(first.results.map(\.action) == ["pull", "share"] && first.results.map(\.exitCode) == [0, 7] && first.failure != nil, "real first publication fails only after sync")
        let successfulSync = coordinator.lastSuccessfulSync(fixture.app.id)
        try Self.expect(successfulSync == first.results.first?.finishedAt, "successful sync retained after failed publisher")
        try Self.expect(try fixture.marker("sync") == "sync\n" && fixture.marker("publish") == "A\n", "failed real publisher recorded A")
        try fixture.nextNative.write(to: fixture.nativeURL)
        let retryValues = fixture.registry.appConfigWithNativeValues(fixture.app, manifest: fixture.manifest, includeSecrets: false).configValues
        try Self.expect(retryValues == fixture.values, "retry command inputs still contain saved A")
        let retryPermit = fixture.registry.nativePublicationGuard(for: fixture.installation, configValues: retryValues, runner: fixture.runner)
        let retry = try coordinator.run(
            installation: fixture.installation, config: fixture.app, configValues: retryValues,
            action: "pull", now: now.addingTimeInterval(900), scheduledInterval: 900,
            allowShare: {
                fixture.registry.matchesPersistedRawAppConfig(fixture.app) && retryPermit()
            })
        { action in
            try fixture.runner.run(
                installation: fixture.installation, configValues: retryValues, action: action, timeoutSeconds: 5)
        }
        try Self.expect(retry.results.isEmpty && retry.failure == nil, "menu-shaped retry is authorization denial, not a child error")
        try Self.expect(try fixture.marker("sync") == "sync\n" && fixture.marker("publish") == "A\n", "denied retry neither resyncs nor invokes publisher")
        try Self.expect(coordinator.lastSuccessfulSync(fixture.app.id) == successfulSync, "denied retry preserves successful sync time")
        try Self.expect(try Data(contentsOf: fixture.nativeURL) == fixture.nextNative, "retry leaves native B intact")
        try fixture.expectMainUnchanged()
    }

    private static func testNativePublicationMissingValues() throws {
        let fixture = try NativePublicationFixture(change: "unchanged", destination: nil)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let absent = fixture.registry.nativePublicationGuard(for: fixture.installation, configValues: [:], runner: fixture.runner)
        try Self.expect(absent(), "readable absent/absent ignores manifest default A")
        let coordinator = CrawlActionCoordinator()
        let baseline = fixture.registry.appConfigWithNativeValues(fixture.app, manifest: fixture.manifest, includeSecrets: false)
        let outcome = try coordinator.run(
            installation: fixture.installation, config: baseline, configValues: [:], action: "pull",
            allowShare: { fixture.registry.matchesPersistedAppConfig(baseline, manifest: fixture.manifest) && absent() })
        { action in
            try fixture.runner.run(installation: fixture.installation, configValues: [:], action: action, timeoutSeconds: 5)
        }
        try Self.expect(outcome.failure == nil && outcome.results.map(\.action) == ["pull", "share"], "absent values keep the child runnable")
        try Self.expect(try fixture.marker("publish") == "child-default\n", "child default is not replaced by manifest default")
        let expectedA = fixture.registry.nativePublicationGuard(for: fixture.installation, configValues: ["destination": "A"], runner: fixture.runner)
        try Self.expect(!expectedA(), "saved A versus absent native is denied despite default A")
        try Data("[share]\nrepo_path = \"A\"\n".utf8).write(to: fixture.nativeURL)
        try Self.expect(!absent() && expectedA(), "absent/A differs and A/A matches")
        try FileManager.default.removeItem(at: fixture.nativeURL)
        let lazy = fixture.registry.nativePublicationGuard(for: fixture.installation, configValues: ["destination": "A"], runner: fixture.runner)
        try Data("[share]\nrepo_path = \"A\"\n".utf8).write(to: fixture.nativeURL)
        try Self.expect(lazy(), "factory reads only when its returned guard is invoked")
        try FileManager.default.removeItem(at: fixture.nativeURL)
        try Self.expect(!absent() && !expectedA(), "missing selected config is not readable absence")
        try Data([0xff, 0xfe, 0xff]).write(to: fixture.nativeURL)
        try Self.expect(!absent() && !expectedA(), "invalid UTF-8 is refused")
        try Self.expect(try Data(contentsOf: fixture.nativeURL) == Data([0xff, 0xfe, 0xff]), "invalid bytes are not repaired")
        try FileManager.default.removeItem(at: fixture.nativeURL)
        try FileManager.default.createDirectory(at: fixture.nativeURL, withIntermediateDirectories: false)
        try Self.expect(!absent(), "selected config read errors are refused")
        try FileManager.default.removeItem(at: fixture.nativeURL)
        var noMapping = fixture.installation
        noMapping.manifest.configOptions = [
            .init(id: "env", label: "Environment", envVar: "PUBLICATION_FIXTURE_VALUE", configKey: "share.repo_path"),
            .init(id: "fixture_secret", label: "Fixture secret", kind: .secret, configKey: "auth.fixture"),
        ]
        try Self.expect(fixture.registry.nativePublicationGuard(for: noMapping, configValues: [:], runner: fixture.runner)(), "env-backed and secret mappings require no added file read")
        var unavailable = fixture.installation
        unavailable.configPathOverride = nil
        unavailable.manifest.paths.defaultConfig = nil
        try Self.expect(!fixture.registry.nativePublicationGuard(for: unavailable, configValues: [:], runner: fixture.runner)(), "selected route without a path is denied")
        var remote = fixture.installation
        remote.manifest.execution = .init(kind: .ssh)
        try Self.expect(fixture.registry.nativePublicationGuard(for: remote, configValues: [:], runner: fixture.runner)(), "remote predicate performs no local file probe")
    }
}

private struct NativePublicationFixture {
    let directory: URL
    let nativeURL: URL
    let mainURL: URL
    let manifest: CrawlAppManifest
    let app: CrawlBarAppConfig
    let registry: CrawlAppRegistry
    let nativeStore: CrawlNativeConfigStore
    let installation: CrawlAppInstallation
    let values: [String: String]
    let runner: CrawlCommandRunner
    let initialMain: Data
    let initialNative: Data
    let nextNative: Data
    let modificationDate: Date

    init(change: String, destination: String? = "A") throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("crawlbar-native-publication-\(UUID())")
        let appsURL = directory.appendingPathComponent("apps")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: appsURL, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let nativeURL = directory.appendingPathComponent("native.toml")
        let mainURL = directory.appendingPathComponent("config.json")
        let scriptURL = directory.appendingPathComponent("child.sh")
        try Self.script.write(to: scriptURL, atomically: true, encoding: .utf8)
        var specification = CrawlBarSelfTest.nativeFixtureManifest(commands: [
            "pull": [scriptURL.path, "sync", change], "share": [scriptURL.path, "publish", change],
        ], binary: "/bin/sh")
        specification.paths = .init(defaultConfig: nativeURL.path, configEnv: "NATIVE_PUBLICATION_CONFIG")
        specification.configOptions = [
            .init(id: "destination", label: "Destination", defaultValue: "A", configKey: "share.repo_path"),
            .init(id: "fixture_secret", label: "Fixture secret", kind: .secret, configKey: "auth.fixture"),
        ]
        try CrawlCoding.makeJSONEncoder().encode(specification).write(to: appsURL.appendingPathComponent("fixture.json"))
        let app = CrawlBarAppConfig(
            id: specification.id, binaryPath: "/bin/sh", configPath: nativeURL.path,
            preferredRefreshAction: "pull", shareEnabled: true, shareAfterRefresh: true, preferredShareAction: "share",
            configValues: destination.map { ["destination": $0] } ?? [:])
        let config = CrawlBarConfig(manifestDirectories: [appsURL.path], apps: [app])
        let catalog = CrawlManifestCatalog(scanCache: CrawlManifestScanCache())
        guard let manifest = catalog.manifest(for: app.id, config: config) else {
            throw SelfTestError.failed("external publication manifest was not discovered")
        }
        try CrawlBarSelfTest.expect(
            catalog.diagnostics(config: config).isEmpty && manifest == specification
                && manifest.configOptions[0].envVar == nil && manifest.configOptions[0].configKey == "share.repo_path",
            "decoded external manifest retains config-only destination and fixed child commands")
        let store = CrawlBarConfigStore(fileURL: mainURL, cache: CrawlBarConfigCache())
        let nativeStore = CrawlNativeConfigStore(cache: CrawlNativeConfigCache())
        let registry = CrawlAppRegistry(configStore: store, catalog: catalog, nativeConfigStore: nativeStore)
        try store.save(config)
        var nativeApp = app
        nativeApp.configValues["fixture_secret"] = UUID().uuidString
        try nativeStore.write(appConfig: nativeApp, manifest: manifest)
        let initialNative = try Data(contentsOf: nativeURL)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try fm.setAttributes([.modificationDate: fixedDate], ofItemAtPath: nativeURL.path)
        let attributes = try fm.attributesOfItem(atPath: nativeURL.path)
        guard let date = attributes[.modificationDate] as? Date else { throw SelfTestError.failed("native fixture has no mtime") }
        try CrawlBarSelfTest.expect(date == fixedDate, "native fixture establishes exact whole-second mtime before cache prime")
        let values = registry.appConfigWithNativeValues(app, manifest: manifest, includeSecrets: false).configValues
        let persisted = try store.load(includeSecrets: false)?.apps.first { $0.id == app.id }
        let nativeValues = try nativeStore.read(path: nativeURL.path, manifest: manifest)
        try CrawlBarSelfTest.expect(persisted == app && values == app.configValues && nativeValues["destination"] == destination, "main/native A and nonsecret command inputs agree before execution")
        let nextNative: Data
        if change == "invalid-utf8" {
            nextNative = Data([0xff, 0xfe, 0xff])
        } else if change == "secret-only" {
            let nextURL = directory.appendingPathComponent("next-secret.toml")
            var next = nativeApp
            next.configPath = nextURL.path
            next.configValues["fixture_secret"] = UUID().uuidString
            try nativeStore.write(appConfig: next, manifest: manifest)
            nextNative = try Data(contentsOf: nextURL)
        } else {
            nextNative = Data("[share]\nrepo_path = \"B\"\n".utf8)
        }
        try nextNative.write(to: directory.appendingPathComponent("native-next.toml"))
        self.directory = directory
        self.nativeURL = nativeURL
        self.mainURL = mainURL
        self.manifest = manifest
        self.app = app
        self.registry = registry
        self.nativeStore = nativeStore
        self.values = values
        self.installation = CrawlAppInstallation(
            manifest: manifest, binaryPath: "/bin/sh", configPathOverride: nativeURL.path, configValues: values)
        self.runner = CrawlCommandRunner(environment: ["HOME": directory.path, "TMPDIR": directory.path, "PATH": "/usr/bin:/bin"])
        self.initialMain = try Data(contentsOf: mainURL)
        self.initialNative = initialNative
        self.nextNative = nextNative
        self.modificationDate = date
    }

    func marker(_ name: String) throws -> String {
        let url = self.directory.appendingPathComponent("\(name).marker")
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func nativeModificationDate() throws -> Date? {
        try FileManager.default.attributesOfItem(atPath: self.nativeURL.path)[.modificationDate] as? Date
    }

    func expectMainUnchanged() throws {
        try CrawlBarSelfTest.expect(try Data(contentsOf: self.mainURL) == self.initialMain, "main config bytes remain unchanged")
    }

    private static let script = #"""
    set -eu
    case "$1" in
      sync)
        printf 'sync\n' >> "$HOME/sync.marker"
        case "$2" in
          changed|same-mtime|secret-only|invalid-utf8) /bin/cp "$HOME/native-next.toml" "$NATIVE_PUBLICATION_CONFIG" ;;
          missing) /bin/rm "$NATIVE_PUBLICATION_CONFIG" ;;
        esac
        ;;
      publish)
        destination=child-default
        if [ -f "$NATIVE_PUBLICATION_CONFIG" ]; then
          observed=$(/usr/bin/sed -n 's/^repo_path = "\(.*\)"$/\1/p' "$NATIVE_PUBLICATION_CONFIG")
          if [ -n "$observed" ]; then destination=$observed; fi
        fi
        printf '%s\n' "$destination" >> "$HOME/publish.marker"
        if [ "$2" = retry ]; then exit 7; fi
        ;;
      *) exit 64 ;;
    esac
    """#
}
