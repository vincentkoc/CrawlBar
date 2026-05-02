import Foundation

public struct CrawlAppRegistry: @unchecked Sendable {
    private let configStore: CrawlBarConfigStore
    private let catalog: CrawlManifestCatalog
    private let resolver: CrawlExecutableResolver

    public init(
        configStore: CrawlBarConfigStore = CrawlBarConfigStore(),
        catalog: CrawlManifestCatalog = CrawlManifestCatalog(),
        resolver: CrawlExecutableResolver = CrawlExecutableResolver())
    {
        self.configStore = configStore
        self.catalog = catalog
        self.resolver = resolver
    }

    public func loadConfig() throws -> CrawlBarConfig {
        try self.configStore.loadOrCreateDefault()
    }

    public func installations(includeDisabled: Bool = true) throws -> [CrawlAppInstallation] {
        let config = try self.loadConfig()
        return config.apps.compactMap { appConfig in
            guard let manifest = self.catalog.manifest(for: appConfig.id, config: config) else { return nil }
            let isAvailable = manifest.availability == .available
            let enabled = isAvailable && appConfig.enabled
            guard includeDisabled || enabled else { return nil }
            let requestedBinary = appConfig.binaryPath?.nilIfBlank ?? manifest.binary.name
            let resolvedBinary = isAvailable ? self.resolver.resolve(requestedBinary) : nil
            return CrawlAppInstallation(
                manifest: manifest,
                binaryPath: resolvedBinary,
                configPathOverride: appConfig.configPath,
                enabled: enabled)
        }
    }

    public func installation(for id: CrawlAppID) throws -> CrawlAppInstallation? {
        try self.installations(includeDisabled: true).first { $0.id == id }
    }

    public func availableInstallations() throws -> [CrawlAppInstallation] {
        try self.installations(includeDisabled: false).filter { $0.binaryPath != nil }
    }
}
