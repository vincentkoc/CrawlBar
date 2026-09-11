import Foundation

public struct CrawlAppRegistry: @unchecked Sendable {
    private let configStore: CrawlBarConfigStore
    private let catalog: CrawlManifestCatalog
    private let resolver: CrawlExecutableResolver
    private let nativeConfigStore: CrawlNativeConfigStore

    public init(
        configStore: CrawlBarConfigStore = CrawlBarConfigStore(),
        catalog: CrawlManifestCatalog = CrawlManifestCatalog(),
        resolver: CrawlExecutableResolver = CrawlExecutableResolver(),
        nativeConfigStore: CrawlNativeConfigStore = CrawlNativeConfigStore())
    {
        self.configStore = configStore
        self.catalog = catalog
        self.resolver = resolver
        self.nativeConfigStore = nativeConfigStore
    }

    public func loadConfig(includeSecrets: Bool = false) throws -> CrawlBarConfig {
        try self.configStore.loadOrCreateDefault(includeSecrets: includeSecrets)
    }

    public func installations(includeDisabled: Bool = true, includeSecrets: Bool = false) throws -> [CrawlAppInstallation] {
        let loadedConfig = try self.loadConfig()
        let manifests = Dictionary(uniqueKeysWithValues: self.catalog
            .manifests(config: loadedConfig)
            .map { ($0.id, $0) })
        let knownIDs = manifests.keys.sorted()
        let config = loadedConfig.normalized(knownIDs: knownIDs)
        return config.apps.compactMap { appConfig in
            guard let manifest = manifests[appConfig.id] else { return nil }
            let nativeAppConfig = self.appConfigWithNativeValues(
                appConfig,
                manifest: manifest,
                includeSecrets: includeSecrets)
            let isAvailable = manifest.availability == .available
            let enabled = isAvailable && nativeAppConfig.enabled
            guard includeDisabled || enabled else { return nil }
            let executionKind = manifest.executionKind(configValues: nativeAppConfig.configValues)
            let defaultBinary = executionKind == .ssh
                ? "ssh"
                : Self.effectiveBinaryName(manifest: manifest, configValues: nativeAppConfig.configValues)
            let requestedBinary = executionKind == .ssh
                ? defaultBinary
                : nativeAppConfig.binaryPath?.nilIfBlank ?? defaultBinary
            let resolvedBinary = isAvailable ? self.resolver.resolve(requestedBinary) : nil
            let resolvedAppConfig = includeSecrets && enabled && resolvedBinary != nil
                ? self.configStore.appConfigWithSecrets(nativeAppConfig, manifest: manifest)
                : nativeAppConfig
            let refreshFrequency = resolvedAppConfig.refreshFrequency ?? config.refreshFrequency
            let staleAfterSeconds = resolvedAppConfig.autoRefreshEnabled ? refreshFrequency.seconds.map(Int.init) : nil
            return CrawlAppInstallation(
                manifest: manifest,
                binaryPath: resolvedBinary,
                configPathOverride: resolvedAppConfig.configPath,
                configValues: resolvedAppConfig.configValues,
                staleAfterSeconds: staleAfterSeconds,
                enabled: enabled)
        }
    }

    public func installationsForStatus(includeDisabled: Bool = true) throws -> [CrawlAppInstallation] {
        try self.installations(includeDisabled: includeDisabled, includeSecrets: false).map { installation in
            guard installation.enabled,
                  installation.binaryPath != nil,
                  installation.manifest.needsSecretsForStatus
            else { return installation }
            return self.installationWithSecrets(installation)
        }
    }

    public func installation(for id: CrawlAppID, includeSecrets: Bool = false) throws -> CrawlAppInstallation? {
        try self.installations(includeDisabled: true, includeSecrets: includeSecrets).first { $0.id == id }
    }

    public func installationForStatus(for id: CrawlAppID) throws -> CrawlAppInstallation? {
        guard let installation = try self.installation(for: id, includeSecrets: false) else { return nil }
        guard installation.enabled,
              installation.binaryPath != nil,
              installation.manifest.needsSecretsForStatus
        else { return installation }
        return self.installationWithSecrets(installation)
    }

    public func availableInstallations(includeSecrets: Bool = false) throws -> [CrawlAppInstallation] {
        try self.installations(includeDisabled: false, includeSecrets: includeSecrets).filter { $0.binaryPath != nil }
    }

    package func executionConfigValues(for installation: CrawlAppInstallation) -> [String: String] {
        // Keep credentials separate from installation metadata so UI and log identities stay secret-free.
        let appConfig = CrawlBarAppConfig(
            id: installation.id,
            enabled: installation.enabled,
            configPath: installation.configPathOverride,
            configValues: installation.configValues)
        let nativeConfig = self.appConfigWithNativeValues(
            appConfig,
            manifest: installation.manifest,
            includeSecrets: true)
        return self.configStore
            .appConfigWithSecrets(nativeConfig, manifest: installation.manifest)
            .configValues
    }

    package func statusConfigValues(for installation: CrawlAppInstallation) -> [String: String] {
        guard installation.enabled,
              installation.binaryPath != nil,
              installation.manifest.needsSecretsForStatus
        else { return installation.configValues }
        return self.executionConfigValues(for: installation)
    }

    public func appConfigWithNativeValues(
        _ appConfig: CrawlBarAppConfig,
        manifest: CrawlAppManifest,
        includeSecrets: Bool = true)
        -> CrawlBarAppConfig
    {
        var copy = appConfig
        copy.configValues = self.nativeConfigStore.resolvedConfigValues(
            appConfig: appConfig,
            manifest: manifest,
            includeSecrets: includeSecrets)
        return copy
    }

    package func matchesPersistedRawAppConfig(_ captured: CrawlBarAppConfig) -> Bool {
        guard let config = try? self.configStore.loadUncached(),
              let current = config.apps.first(where: { $0.id == captured.id })
        else { return false }
        // The scheduler captures raw config; native values have a separate publication guard.
        return current == captured
    }

    package func matchesPersistedAppConfig(_ captured: CrawlBarAppConfig, manifest: CrawlAppManifest) -> Bool {
        guard let config = try? self.configStore.loadUncached(),
              let current = config.apps.first(where: { $0.id == captured.id })
        else { return false }
        // Keep the pre-action values frozen; only enrich the current config.
        let secretIDs = Set(manifest.configOptions.filter { $0.kind == .secret }.map(\.id))
        var baseline = captured
        baseline.configValues = baseline.configValues.filter { !secretIDs.contains($0.key) }
        return self.appConfigWithNativeValues(current, manifest: manifest, includeSecrets: false) == baseline
    }

    package func nativePublicationGuard(
        for installation: CrawlAppInstallation,
        configValues: [String: String],
        runner: CrawlCommandRunner)
        -> @Sendable () -> Bool
    {
        let manifest = installation.manifest
        guard manifest.executionKind(configValues: configValues) == .local else { return { true } }
        let optionIDs = Set(manifest.configOptions.filter {
            $0.kind != .secret && $0.configKey?.nilIfBlank != nil && $0.envVar?.nilIfBlank == nil
        }.map(\.id))
        guard !optionIDs.isEmpty else { return { true } }
        // Freeze only the declared nonsecret values supplied to this execution, including retries.
        let expected = configValues.filter { optionIDs.contains($0.key) }
        let path = runner.nativePublicationConfigPath(for: installation, configValues: configValues)
        let nativeStore = self.nativeConfigStore
        return {
            guard let path,
                  let current = try? nativeStore.publicationValues(path: path, manifest: manifest, optionIDs: optionIDs)
            else { return false }
            return current == expected
        }
    }

    private func installationWithSecrets(_ installation: CrawlAppInstallation) -> CrawlAppInstallation {
        return CrawlAppInstallation(
            manifest: installation.manifest,
            binaryPath: installation.binaryPath,
            configPathOverride: installation.configPathOverride,
            configValues: self.executionConfigValues(for: installation),
            staleAfterSeconds: installation.staleAfterSeconds,
            enabled: installation.enabled)
    }

    private static func effectiveBinaryName(manifest: CrawlAppManifest, configValues: [String: String]) -> String {
        guard manifest.id == BuiltInCrawlApps.birdclawID else {
            return manifest.binary.name
        }
        let accessPath = (configValues["access_path"]?.nilIfBlank ?? "bird")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return accessPath == "birdclaw" ? "birdclaw" : manifest.binary.name
    }
}
