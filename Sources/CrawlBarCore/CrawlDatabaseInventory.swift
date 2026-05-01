import Foundation

public enum CrawlDatabaseInventory {
    public static func enrich(_ status: CrawlAppStatus, manifest: CrawlAppManifest) -> CrawlAppStatus {
        guard status.databases.isEmpty else { return status }
        var copy = status
        copy.databases = Self.resources(for: status, manifest: manifest)
        return copy
    }

    public static func resources(for status: CrawlAppStatus, manifest: CrawlAppManifest) -> [CrawlDatabaseResource] {
        switch manifest.id {
        case BuiltInCrawlApps.gitcrawlID:
            return Self.gitcrawlResources(status: status)
        case BuiltInCrawlApps.slacrawlID:
            return Self.singleSQLiteResource(status: status, manifest: manifest, label: "Slack archive", role: "Workspace database")
        case BuiltInCrawlApps.discrawlID:
            return Self.singleSQLiteResource(status: status, manifest: manifest, label: "Discord archive", role: "Guild database")
        case BuiltInCrawlApps.notcrawlID:
            return Self.notcrawlResources(status: status, manifest: manifest)
        default:
            return Self.singleSQLiteResource(status: status, manifest: manifest, label: "Archive database", role: nil)
        }
    }

    private static func gitcrawlResources(status: CrawlAppStatus) -> [CrawlDatabaseResource] {
        let activePath = status.databasePath.map(Self.normalizedPath)
        let storesURL = Self.gitcrawlStoresURL(activeDatabasePath: activePath)
        let storeURLs = (try? FileManager.default.contentsOfDirectory(
            at: storesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []

        var resources: [CrawlDatabaseResource] = []
        for storeURL in storeURLs {
            let dataURL = storeURL.appendingPathComponent("data", isDirectory: true)
            let databaseURLs = Self.sqliteFiles(in: dataURL)
            for databaseURL in databaseURLs {
                let path = Self.normalizedPath(databaseURL.path)
                let isPrimary = path == activePath
                resources.append(Self.resource(
                    label: Self.gitcrawlLabel(for: databaseURL, storeName: storeURL.lastPathComponent),
                    kind: .sqlite,
                    role: isPrimary ? "Active repository database" : "Repository database",
                    path: path,
                    isPrimary: isPrimary,
                    counts: isPrimary ? status.counts : []))
            }
        }

        if resources.isEmpty, let activePath {
            resources.append(Self.resource(
                label: Self.gitcrawlLabel(for: URL(fileURLWithPath: activePath), storeName: nil),
                kind: .sqlite,
                role: "Active repository database",
                path: activePath,
                isPrimary: true,
                counts: status.counts))
        }

        return resources.sorted {
            if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
            return $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
    }

    private static func notcrawlResources(status: CrawlAppStatus, manifest: CrawlAppManifest) -> [CrawlDatabaseResource] {
        var resources = Self.singleSQLiteResource(
            status: status,
            manifest: manifest,
            label: "Notion archive",
            role: "Workspace database")

        let cacheURL = URL(fileURLWithPath: PathExpander.expandHome(manifest.paths.defaultCache ?? "~/.notcrawl/cache"), isDirectory: true)
        for databaseURL in Self.sqliteFiles(in: cacheURL) {
            resources.append(Self.resource(
                label: "Desktop cache",
                kind: .cache,
                role: databaseURL.deletingPathExtension().lastPathComponent,
                path: Self.normalizedPath(databaseURL.path),
                isPrimary: false))
        }
        return resources
    }

    private static func singleSQLiteResource(
        status: CrawlAppStatus,
        manifest: CrawlAppManifest,
        label: String,
        role: String?)
        -> [CrawlDatabaseResource]
    {
        guard let path = Self.primaryDatabasePath(status: status, manifest: manifest) else { return [] }
        return [
            Self.resource(
                label: label,
                kind: .sqlite,
                role: role,
                path: path,
                isPrimary: true,
                counts: status.counts),
        ]
    }

    private static func primaryDatabasePath(status: CrawlAppStatus, manifest: CrawlAppManifest) -> String? {
        if let path = status.databasePath?.nilIfBlank {
            return Self.normalizedPath(path)
        }
        if let path = manifest.paths.defaultDatabase?.nilIfBlank {
            return Self.normalizedPath(PathExpander.expandHome(path))
        }
        return nil
    }

    private static func gitcrawlStoresURL(activeDatabasePath: String?) -> URL {
        if let activeDatabasePath {
            return URL(fileURLWithPath: activeDatabasePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        return URL(fileURLWithPath: PathExpander.expandHome("~/.config/gitcrawl/stores"), isDirectory: true)
    }

    private static func sqliteFiles(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { ["db", "sqlite", "sqlite3"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func resource(
        label: String,
        kind: CrawlDatabaseKind,
        role: String?,
        path: String,
        isPrimary: Bool,
        counts: [CrawlCount] = [])
        -> CrawlDatabaseResource
    {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return CrawlDatabaseResource(
            id: path,
            label: label,
            kind: kind,
            role: role,
            path: path,
            isPrimary: isPrimary,
            bytes: values?.fileSize,
            modifiedAt: values?.contentModificationDate,
            counts: counts)
    }

    private static func gitcrawlLabel(for databaseURL: URL, storeName: String?) -> String {
        let baseName = databaseURL.lastPathComponent
            .replacingOccurrences(of: ".sync.db", with: "")
            .replacingOccurrences(of: ".db", with: "")
            .replacingOccurrences(of: "__", with: "/")
        guard let storeName, !storeName.isEmpty else { return baseName }
        return "\(baseName) · \(storeName)"
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: PathExpander.expandHome(path)).standardizedFileURL.path
    }
}
