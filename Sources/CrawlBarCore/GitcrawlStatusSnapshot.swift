import Foundation

public enum GitcrawlStatusSnapshot {
    public static func status(for installation: CrawlAppInstallation) -> CrawlAppStatus? {
        guard installation.id == BuiltInCrawlApps.gitcrawlID else { return nil }
        guard let reportURL = Self.reportURL(for: installation),
              let data = try? Data(contentsOf: reportURL),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        let portable = object["portable"] as? [String: Any]
        let threads = portable?["threads"] as? [String: Any]
        let clusters = portable?["clusters"] as? [String: Any]
        let repository = object["repository"] as? [String: Any]
        let latestUpdatedAt = Self.date(threads?["latestUpdatedAt"])
        let totalThreads = Self.int(threads?["total"])
        let openThreads = Self.int(threads?["open"])
        let clusterGroups = Self.int(clusters?["groups"])

        let counts = [
            totalThreads.map { CrawlCount(id: "threads", label: "Threads", value: $0) },
            openThreads.map { CrawlCount(id: "open_threads", label: "Open Threads", value: $0) },
            clusterGroups.map { CrawlCount(id: "clusters", label: "Clusters", value: $0) },
            repository == nil ? nil : CrawlCount(id: "repositories", label: "Repositories", value: 1),
        ].compactMap { $0 }

        let state: CrawlAppState = latestUpdatedAt.map {
            Date().timeIntervalSince($0) > 86_400 ? .stale : .current
        } ?? .current
        let freshness = latestUpdatedAt.map {
            let ageSeconds = max(0, Int(Date().timeIntervalSince($0)))
            return CrawlFreshness(
                status: ageSeconds > 86_400 ? .stale : .current,
                ageSeconds: ageSeconds,
                staleAfterSeconds: 86_400)
        }

        let status = CrawlAppStatus(
            appID: installation.id,
            state: state,
            summary: Self.summary(counts: counts),
            configPath: Self.configPath(for: installation)?.path,
            databasePath: Self.databasePath(for: installation),
            lastSyncAt: latestUpdatedAt,
            counts: counts,
            freshness: freshness)
        return CrawlDatabaseInventory.enrich(status, manifest: installation.manifest)
    }

    private static func summary(counts: [CrawlCount]) -> String {
        let visible = counts.prefix(2).map { "\($0.value) \($0.label.lowercased())" }
        return visible.isEmpty ? "Git Crawl status is current" : visible.joined(separator: ", ")
    }

    private static func reportURL(for installation: CrawlAppInstallation) -> URL? {
        if let databasePath = Self.databasePath(for: installation) {
            let databaseURL = URL(fileURLWithPath: databasePath)
            let reportURL = databaseURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("reports/latest-status.json")
            if FileManager.default.fileExists(atPath: reportURL.path) {
                return reportURL
            }
        }

        let storesURL = URL(fileURLWithPath: PathExpander.expandHome("~/.config/gitcrawl/stores"), isDirectory: true)
        guard let storeURLs = try? FileManager.default.contentsOfDirectory(
            at: storesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
        else { return nil }

        var candidates: [(url: URL, modifiedAt: Date)] = []
        for storeURL in storeURLs {
            let reportURL = storeURL.appendingPathComponent("reports/latest-status.json")
            guard FileManager.default.fileExists(atPath: reportURL.path) else { continue }
            let values = try? reportURL.resourceValues(forKeys: [.contentModificationDateKey])
            candidates.append((reportURL, values?.contentModificationDate ?? .distantPast))
        }
        return candidates.sorted { $0.modifiedAt > $1.modifiedAt }.first?.url
    }

    private static func databasePath(for installation: CrawlAppInstallation) -> String? {
        if let configURL = Self.configPath(for: installation),
           let content = try? String(contentsOf: configURL, encoding: .utf8),
           let parsed = Self.tomlString("db_path", in: content)
        {
            return PathExpander.expandHome(parsed)
        }
        return installation.manifest.paths.defaultDatabase.map { PathExpander.expandHome($0) }
    }

    private static func configPath(for installation: CrawlAppInstallation) -> URL? {
        if let override = installation.configPathOverride?.nilIfBlank {
            return URL(fileURLWithPath: PathExpander.expandHome(override))
        }
        if let envName = installation.manifest.paths.configEnv,
           let envValue = ProcessInfo.processInfo.environment[envName]?.nilIfBlank
        {
            return URL(fileURLWithPath: PathExpander.expandHome(envValue))
        }
        guard let defaultConfig = installation.manifest.paths.defaultConfig else { return nil }
        return URL(fileURLWithPath: PathExpander.expandHome(defaultConfig))
    }

    private static func tomlString(_ key: String, in content: String) -> String? {
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            let pieces = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            guard pieces[0].trimmingCharacters(in: .whitespaces) == key else { continue }
            return pieces[1]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .nilIfBlank
        }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String, let trimmed = string.nilIfBlank else { return nil }
        return ISO8601DateFormatter.crawlBarDate(from: trimmed)
    }
}
