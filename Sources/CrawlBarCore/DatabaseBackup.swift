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
        let files = status.databases
            .filter { $0.kind == .sqlite || $0.kind == .cache }
            .compactMap(\.path)
            .map { URL(fileURLWithPath: PathExpander.expandHome($0)) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        guard !files.isEmpty else {
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
        for source in files {
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            copied.append(destination.path)
        }

        return CrawlDatabaseBackup(appID: status.appID, directory: directory.path, files: copied)
    }
}
