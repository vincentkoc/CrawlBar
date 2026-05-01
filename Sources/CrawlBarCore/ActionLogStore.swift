import Foundation

public struct CrawlActionLogStore: @unchecked Sendable {
    public let directoryURL: URL
    private let fileManager: FileManager

    public init(
        directoryURL: URL = Self.defaultDirectory(),
        fileManager: FileManager = .default)
    {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    public func save(_ result: CrawlCommandResult) throws -> URL {
        if !self.fileManager.fileExists(atPath: self.directoryURL.path) {
            try self.fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
        }
        let timestamp = ISO8601DateFormatter.crawlBarFormatter()
            .string(from: result.finishedAt)
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(result.appID.rawValue)-\(result.action)-\(timestamp).json"
        let url = self.directoryURL.appendingPathComponent(filename)
        let data = try CrawlCoding.makeJSONEncoder().encode(result)
        try data.write(to: url, options: [.atomic])
        #if os(macOS) || os(Linux)
        try self.fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path)
        #endif
        return url
    }

    public func recent(limit: Int = 20) -> [URL] {
        guard let urls = try? self.fileManager.contentsOfDirectory(
            at: self.directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey])
        else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                self.modificationDate(lhs) > self.modificationDate(rhs)
            }
            .prefix(limit)
            .map { $0 }
    }

    public static func defaultDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".crawlbar", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    private func modificationDate(_ url: URL) -> Date {
        ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
    }
}
