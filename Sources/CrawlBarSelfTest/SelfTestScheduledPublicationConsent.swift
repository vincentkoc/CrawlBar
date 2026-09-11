import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func testScheduledPublicationConsent() throws {
        for retry in [false, true] {
            for change in ScheduledConsentChange.allCases {
                let fixture = try ScheduledConsentFixture(change: change, failFirstPublication: retry)
                defer { try? FileManager.default.removeItem(at: fixture.directory) }
                let coordinator = CrawlActionCoordinator()
                let now = Date(timeIntervalSince1970: 1_700_000_100)
                var successfulSync: Date?
                if retry {
                    let first = try fixture.run(coordinator, now: now)
                    try Self.expect(
                        first.results.map(\.action) == ["pull", "share"]
                            && first.results.map(\.exitCode) == [0, 7] && first.failure != nil,
                        "scheduled retry starts with a real failed publisher after successful sync")
                    successfulSync = coordinator.lastSuccessfulSync(fixture.app.id)
                    try Self.expect(successfulSync == first.results.first?.finishedAt, "failed publication retains successful sync time")
                    try fixture.changeMainConfig()
                }
                let outcome = try fixture.run(coordinator, now: retry ? now.addingTimeInterval(900) : now) {
                    if !retry { try fixture.changeMainConfig() }
                }
                let publish = change == .unchanged
                let expectedActions = retry ? (publish ? ["share"] : []) : (publish ? ["pull", "share"] : ["pull"])
                try Self.expect(outcome.failure == nil && outcome.results.map(\.action) == expectedActions, "scheduled consent phases \(change), retry \(retry)")
                try Self.expect(try fixture.marker("sync") == "sync\n", "scheduled consent never repeats successful sync")
                let expectedPublish = (retry ? "publish\n" : "") + (publish ? "publish\n" : "")
                try Self.expect(try fixture.marker("publish") == expectedPublish, "real publication child obeys consent \(change), retry \(retry)")
                if !retry && !publish {
                    try Self.expect(
                        !FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("publish.marker").path),
                        "denied initial publication creates no child marker")
                }
                let expectedSync = retry ? successfulSync : outcome.results.first?.finishedAt
                try Self.expect(coordinator.lastSuccessfulSync(fixture.app.id) == expectedSync, "consent check preserves successful sync")
                try fixture.expectExternalConfigPreserved()
            }
        }
        print("crawlbar scheduled publication consent selftest ok (10 cases)")
    }
}

private enum ScheduledConsentChange: CaseIterable {
    case unchanged
    case shareDisabled
    case afterRefreshDisabled
    case malformed
    case missing
}

private struct ScheduledConsentFixture {
    let directory: URL
    let mainURL: URL
    let nativeURL: URL
    let app: CrawlBarAppConfig
    let registry: CrawlAppRegistry
    let installation: CrawlAppInstallation
    let runner: CrawlCommandRunner
    let values: [String: String]
    let initialMain: Data
    let nextMain: Data
    let initialNative: Data
    let change: ScheduledConsentChange
    let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)

    init(change: ScheduledConsentChange, failFirstPublication: Bool) throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("crawlbar-scheduled-consent-\(UUID())")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let mainURL = directory.appendingPathComponent("config.json")
        let nativeURL = directory.appendingPathComponent("native.toml")
        let scriptURL = directory.appendingPathComponent("child.sh")
        try Self.script.write(to: scriptURL, atomically: true, encoding: .utf8)
        var manifest = CrawlBarSelfTest.nativeFixtureManifest(commands: [
            "pull": [scriptURL.path, "sync"], "share": [scriptURL.path, "publish"],
        ], binary: "/bin/sh")
        manifest.paths = .init(defaultConfig: nativeURL.path, configEnv: "SCHEDULED_NATIVE_CONFIG")
        manifest.configOptions = [
            .init(id: "destination", label: "Destination", configKey: "share.repo_path"),
        ]
        let app = CrawlBarAppConfig(
            id: manifest.id, binaryPath: "/bin/sh", configPath: nativeURL.path,
            preferredRefreshAction: "pull", autoRefreshEnabled: true,
            shareEnabled: true, shareAfterRefresh: true, preferredShareAction: "share")
        let config = CrawlBarConfig(manifestDirectories: [directory.appendingPathComponent("apps").path], apps: [app])
        let initialMain = try CrawlCoding.makeJSONEncoder().encode(config)
        try initialMain.write(to: mainURL)
        let initialNative = Data("[share]\nrepo_path = \"A\"\n".utf8)
        try initialNative.write(to: nativeURL)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        for url in [mainURL, nativeURL] {
            try fm.setAttributes([.modificationDate: fixedDate, .posixPermissions: 0o600], ofItemAtPath: url.path)
            let date = try fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            try CrawlBarSelfTest.expect(date == fixedDate, "scheduled fixture establishes exact mtime before cache prime")
        }
        let store = CrawlBarConfigStore(fileURL: mainURL, cache: CrawlBarConfigCache())
        let registry = CrawlAppRegistry(
            configStore: store, catalog: CrawlManifestCatalog(scanCache: CrawlManifestScanCache()),
            nativeConfigStore: CrawlNativeConfigStore(cache: CrawlNativeConfigCache()))
        let captured = try registry.loadConfig().apps.first { $0.id == app.id }
        try CrawlBarSelfTest.expect(captured == app && app.configValues.isEmpty, "scheduler captures raw main config")
        let installation = CrawlAppInstallation(
            manifest: manifest, binaryPath: "/bin/sh", configPathOverride: nativeURL.path,
            configValues: registry.appConfigWithNativeValues(app, manifest: manifest, includeSecrets: false).configValues)
        let values = registry.executionConfigValues(for: installation)
        try CrawlBarSelfTest.expect(values == ["destination": "A"], "native-only values differ from raw scheduler config")
        let nextMain: Data
        switch change {
        case .unchanged, .missing:
            nextMain = initialMain
        case .malformed:
            nextMain = Data("{".utf8)
        case .shareDisabled, .afterRefreshDisabled:
            var next = config
            if change == .shareDisabled {
                next.apps[0].shareEnabled = false
            } else {
                next.apps[0].shareAfterRefresh = false
            }
            nextMain = try CrawlCoding.makeJSONEncoder().encode(next)
        }
        self.directory = directory
        self.mainURL = mainURL
        self.nativeURL = nativeURL
        self.app = app
        self.registry = registry
        self.installation = installation
        self.values = values
        self.runner = CrawlCommandRunner(environment: [
            "HOME": directory.path, "TMPDIR": directory.path, "PATH": "/usr/bin:/bin",
            "XDG_CONFIG_HOME": directory.path, "XDG_CACHE_HOME": directory.path, "XDG_DATA_HOME": directory.path,
            "FAIL_FIRST_PUBLICATION": failFirstPublication ? "1" : "0",
        ])
        self.initialMain = initialMain
        self.nextMain = nextMain
        self.initialNative = initialNative
        self.change = change
    }

    func run(_ coordinator: CrawlActionCoordinator, now: Date, afterSync: () throws -> Void = {}) throws -> CrawlActionOutcome {
        let nativeGuard = self.registry.nativePublicationGuard(
            for: self.installation, configValues: self.values, runner: self.runner)
        return try coordinator.run(
            installation: self.installation, config: self.app, configValues: self.values,
            action: "pull", now: now, scheduledInterval: 900,
            allowShare: { self.registry.matchesPersistedRawAppConfig(self.app) && nativeGuard() })
        { action in
            let result = try self.runner.run(
                installation: self.installation, configValues: self.values, action: action, timeoutSeconds: 5)
            if action == "pull" { try afterSync() }
            return result
        }
    }

    func changeMainConfig() throws {
        if self.change == .missing {
            try FileManager.default.removeItem(at: self.mainURL)
            return
        }
        // External writes bypass save(), leaving the already-primed cache stale.
        try self.nextMain.write(to: self.mainURL)
        try FileManager.default.setAttributes([.modificationDate: self.modificationDate], ofItemAtPath: self.mainURL.path)
        let date = try FileManager.default.attributesOfItem(atPath: self.mainURL.path)[.modificationDate] as? Date
        try CrawlBarSelfTest.expect(date == self.modificationDate, "external main overwrite restores the exact primed mtime")
        if self.change != .unchanged {
            try CrawlBarSelfTest.expect(self.nextMain != self.initialMain, "same-mtime overwrite actually changes config bytes")
        }
        try CrawlBarSelfTest.expect(
            try self.registry.loadConfig().apps.first { $0.id == self.app.id } == self.app,
            "cached scheduler read still returns old consent after the same-mtime write")
    }

    func expectExternalConfigPreserved() throws {
        if self.change == .missing {
            try CrawlBarSelfTest.expect(!FileManager.default.fileExists(atPath: self.mainURL.path), "missing main config is not recreated")
        } else {
            try CrawlBarSelfTest.expect(try Data(contentsOf: self.mainURL) == self.nextMain, "guard preserves external main config bytes")
            let date = try FileManager.default.attributesOfItem(atPath: self.mainURL.path)[.modificationDate] as? Date
            try CrawlBarSelfTest.expect(date == self.modificationDate, "guard preserves external main mtime")
        }
        try CrawlBarSelfTest.expect(try Data(contentsOf: self.nativeURL) == self.initialNative, "main consent check leaves native config unchanged")
        let nativeDate = try FileManager.default.attributesOfItem(atPath: self.nativeURL.path)[.modificationDate] as? Date
        try CrawlBarSelfTest.expect(nativeDate == self.modificationDate, "main consent check leaves native mtime unchanged")
    }

    func marker(_ name: String) throws -> String {
        let url = self.directory.appendingPathComponent("\(name).marker")
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static let script = #"""
    set -eu
    case "$1" in
      sync) printf 'sync\n' >> "$HOME/sync.marker" ;;
      publish)
        already=0
        if [ -f "$HOME/publish.marker" ]; then already=1; fi
        printf 'publish\n' >> "$HOME/publish.marker"
        if [ "$FAIL_FIRST_PUBLICATION" = 1 ] && [ "$already" = 0 ]; then exit 7; fi
        ;;
      *) exit 64 ;;
    esac
    """#
}
