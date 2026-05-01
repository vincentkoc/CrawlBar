import Foundation

public struct CrawlManifestCatalog: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func manifests(config: CrawlBarConfig) -> [CrawlAppManifest] {
        var manifestsByID: [CrawlAppID: CrawlAppManifest] = [:]
        for manifest in BuiltInCrawlApps.all {
            manifestsByID[manifest.id] = manifest
        }
        for manifest in self.externalManifests(directories: config.manifestDirectories) {
            manifestsByID[manifest.id] = manifest
        }
        return manifestsByID.values.sorted { $0.id < $1.id }
    }

    public func manifest(for id: CrawlAppID, config: CrawlBarConfig) -> CrawlAppManifest? {
        self.manifests(config: config).first { $0.id == id }
    }

    private func externalManifests(directories: [String]) -> [CrawlAppManifest] {
        directories.flatMap { directory -> [CrawlAppManifest] in
            let expanded = PathExpander.expandHome(directory)
            guard let enumerator = self.fileManager.enumerator(
                at: URL(fileURLWithPath: expanded, isDirectory: true),
                includingPropertiesForKeys: nil)
            else {
                return []
            }

            return enumerator.compactMap { item in
                guard let url = item as? URL, url.pathExtension == "json" else { return nil }
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? CrawlCoding.makeJSONDecoder().decode(CrawlAppManifest.self, from: data)
            }
        }
    }
}
