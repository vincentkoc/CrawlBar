import Foundation

public struct CrawlAppRegistry: @unchecked Sendable {
    private let configStore: CrawlBarConfigStore
    private let resolver: CrawlExecutableResolver

    public init(
        configStore: CrawlBarConfigStore = CrawlBarConfigStore(),
        resolver: CrawlExecutableResolver = CrawlExecutableResolver())
    {
        self.configStore = configStore
        self.resolver = resolver
    }

    public func loadConfig() throws -> CrawlBarConfig {
        try self.configStore.loadOrCreateDefault()
    }

    public func installations(includeDisabled: Bool = true) throws -> [CrawlAppInstallation] {
        let config = try self.loadConfig()
        return config.apps.compactMap { appConfig in
            guard includeDisabled || appConfig.enabled else { return nil }
            guard let manifest = BuiltInCrawlApps.manifest(for: appConfig.id) else { return nil }
            let requestedBinary = appConfig.binaryPath?.nilIfBlank ?? manifest.binary.name
            let resolvedBinary = self.resolver.resolve(requestedBinary)
            return CrawlAppInstallation(
                manifest: manifest,
                binaryPath: resolvedBinary,
                configPathOverride: appConfig.configPath,
                enabled: appConfig.enabled)
        }
    }

    public func installation(for id: CrawlAppID) throws -> CrawlAppInstallation? {
        try self.installations(includeDisabled: true).first { $0.id == id }
    }

    public func availableInstallations() throws -> [CrawlAppInstallation] {
        try self.installations(includeDisabled: false).filter { $0.binaryPath != nil }
    }
}
