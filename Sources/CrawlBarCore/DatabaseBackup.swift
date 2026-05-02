import Foundation

public struct CrawlDatabaseBackup: Codable, Equatable, Sendable {
    public var appID: CrawlAppID
    public var directory: String
    public var files: [String]
    public var createdAt: Date

    public init(appID: CrawlAppID, directory: String, files: [String], createdAt: Date = Date()) {
        self.appID = appID
        self.directory = directory
        self.files = files
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case directory
        case files
        case createdAt = "created_at"
    }
}

public enum CrawlDatabaseBackupError: LocalizedError, Sendable {
    case noDatabases(CrawlAppID)

    public var errorDescription: String? {
        switch self {
        case let .noDatabases(appID):
            "\(appID.rawValue) does not expose any local database files to back up"
        }
    }
}

public enum CrawlDatabaseBackupStore {
    public static func defaultDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".crawlbar", isDirectory: true)
            .appendingPathComponent("backups", isDirectory: true)
    }

    public static func backup(status: CrawlAppStatus, root: URL = Self.defaultDirectory()) throws -> CrawlDatabaseBackup {
        let resources = status.databases
            .filter { $0.kind == .sqlite || $0.kind == .cache }
            .compactMap { resource -> (resource: CrawlDatabaseResource, source: URL)? in
                guard let path = resource.path?.nilIfBlank else { return nil }
                let source = URL(fileURLWithPath: PathExpander.expandHome(path))
                guard FileManager.default.fileExists(atPath: source.path) else { return nil }
                return (resource, source)
            }

        guard !resources.isEmpty else {
            throw CrawlDatabaseBackupError.noDatabases(status.appID)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let directory = root
            .appendingPathComponent(status.appID.rawValue, isDirectory: true)
            .appendingPathComponent(timestamp, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var copied: [String] = []
        var usedNames: Set<String> = []
        let basenameCounts = Dictionary(grouping: resources, by: { $0.source.lastPathComponent })
            .mapValues(\.count)
        for entry in resources {
            let destinationName = Self.destinationName(
                for: entry.resource,
                source: entry.source,
                basenameCounts: basenameCounts,
                usedNames: &usedNames)
            let destination = directory.appendingPathComponent(destinationName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: entry.source, to: destination)
            copied.append(destination.path)
        }

        return CrawlDatabaseBackup(appID: status.appID, directory: directory.path, files: copied)
    }

    private static func destinationName(
        for resource: CrawlDatabaseResource,
        source: URL,
        basenameCounts: [String: Int],
        usedNames: inout Set<String>)
        -> String
    {
        let basename = source.lastPathComponent
        let shouldPrefix = (basenameCounts[basename] ?? 0) > 1
        let prefix = Self.safeFilename(resource.label.nilIfBlank ?? resource.id)
        var candidate = shouldPrefix ? "\(prefix)-\(basename)" : basename
        var suffix = 2
        while usedNames.contains(candidate) {
            candidate = "\(prefix)-\(suffix)-\(basename)"
            suffix += 1
        }
        usedNames.insert(candidate)
        return candidate
    }

    private static func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.nilIfBlank ?? "database"
    }
}
