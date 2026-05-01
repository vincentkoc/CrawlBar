import Foundation

public struct CrawlStatusMapper: Sendable {
    public init() {}

    public func status(from result: CrawlCommandResult, manifest: CrawlAppManifest) -> CrawlAppStatus {
        guard result.succeeded else {
            return CrawlAppStatus(
                appID: result.appID,
                state: .error,
                summary: self.failureSummary(result),
                warnings: [],
                errors: [result.stderr.nilIfBlank ?? result.stdout.nilIfBlank ?? "Command exited \(result.exitCode)"])
        }

        guard let object = self.parseObject(result.stdout) else {
            return CrawlAppStatus(
                appID: result.appID,
                state: .unknown,
                summary: result.stdout.nilIfBlank ?? "Command succeeded without JSON output",
                warnings: ["Status command did not return parseable JSON"])
        }

        let status: CrawlAppStatus
        switch manifest.id {
        case BuiltInCrawlApps.gitcrawlID:
            status = self.gitcrawlStatus(object, result: result)
        case BuiltInCrawlApps.slacrawlID:
            status = self.slacrawlStatus(object, result: result)
        case BuiltInCrawlApps.discrawlID:
            status = self.discrawlStatus(object, result: result)
        case BuiltInCrawlApps.notcrawlID:
            status = self.notcrawlStatus(object, result: result)
        default:
            status = self.genericStatus(object, result: result)
        }
        return CrawlDatabaseInventory.enrich(status, manifest: manifest)
    }

    private func gitcrawlStatus(_ object: [String: Any], result: CrawlCommandResult) -> CrawlAppStatus {
        let counts = [
            self.count("threads", "Threads", ["thread_count", "threads"]),
            self.count("open_threads", "Open Threads", ["open_thread_count", "open_threads"]),
            self.count("clusters", "Clusters", ["cluster_count", "clusters"]),
            self.count("repositories", "Repositories", ["repo_count", "repository_count", "repositories"]),
        ].compactMap { self.value($0, in: object) }

        let lastSyncAt = self.dateValue(["last_sync_at", "updated_at", "generated_at"], in: object)
        return CrawlAppStatus(
            appID: result.appID,
            state: self.state(lastSyncAt: lastSyncAt, fallback: .current),
            summary: self.summary(from: counts, fallback: "Git crawl status is current"),
            configPath: self.stringValue(["config_path", "config"], in: object),
            databasePath: self.stringValue(["db_path", "database_path", "database"], in: object),
            lastSyncAt: lastSyncAt,
            counts: counts,
            freshness: self.freshness(lastSyncAt: lastSyncAt))
    }

    private func slacrawlStatus(_ object: [String: Any], result: CrawlCommandResult) -> CrawlAppStatus {
        let counts = [
            self.count("workspaces", "Workspaces", ["workspace_count", "workspaces"]),
            self.count("channels", "Channels", ["channel_count", "channels"]),
            self.count("users", "Users", ["user_count", "users"]),
            self.count("messages", "Messages", ["message_count", "messages"]),
        ].compactMap { self.value($0, in: object) }

        let lastSyncAt = self.dateValue(["last_sync_at", "latest_message_at", "updated_at"], in: object)
        return CrawlAppStatus(
            appID: result.appID,
            state: self.state(lastSyncAt: lastSyncAt, fallback: .current),
            summary: self.summary(from: counts, fallback: "Slack crawl status is current"),
            configPath: self.stringValue(["config_path", "config"], in: object),
            databasePath: self.stringValue(["db_path", "database_path", "database"], in: object),
            lastSyncAt: lastSyncAt,
            counts: counts,
            freshness: self.freshness(lastSyncAt: lastSyncAt),
            share: self.shareStatus(in: object))
    }

    private func discrawlStatus(_ object: [String: Any], result: CrawlCommandResult) -> CrawlAppStatus {
        let counts = [
            self.count("guilds", "Guilds", ["guild_count", "guilds"]),
            self.count("channels", "Channels", ["channel_count", "channels"]),
            self.count("threads", "Threads", ["thread_count", "threads"]),
            self.count("messages", "Messages", ["message_count", "messages"]),
            self.count("members", "Members", ["member_count", "members"]),
            self.count("embedding_backlog", "Embedding Backlog", ["embedding_backlog"]),
        ].compactMap { self.value($0, in: object) }

        let lastSyncAt = self.dateValue(["last_sync_at", "latest_message_at", "updated_at"], in: object)
        return CrawlAppStatus(
            appID: result.appID,
            state: self.state(lastSyncAt: lastSyncAt, fallback: .current),
            summary: self.summary(from: counts, fallback: "Discord crawl status is current"),
            configPath: self.stringValue(["config_path", "config"], in: object),
            databasePath: self.stringValue(["db_path", "database_path", "database"], in: object),
            lastSyncAt: lastSyncAt,
            counts: counts,
            freshness: self.freshness(lastSyncAt: lastSyncAt),
            share: self.shareStatus(in: object))
    }

    private func notcrawlStatus(_ object: [String: Any], result: CrawlCommandResult) -> CrawlAppStatus {
        let counts = [
            self.count("spaces", "Spaces", ["space_count", "spaces"]),
            self.count("users", "Users", ["user_count", "users"]),
            self.count("teams", "Teams", ["team_count", "teams"]),
            self.count("pages", "Pages", ["page_count", "pages"]),
            self.count("blocks", "Blocks", ["block_count", "blocks"]),
            self.count("collections", "Collections", ["collection_count", "collections"]),
            self.count("comments", "Comments", ["comment_count", "comments"]),
            self.count("raw_records", "Raw Records", ["raw_record_count", "raw_records"]),
        ].compactMap { self.value($0, in: object) }

        let lastSyncAt = self.dateValue(["last_sync_at", "last_import_at", "updated_at"], in: object)
        return CrawlAppStatus(
            appID: result.appID,
            state: self.state(lastSyncAt: lastSyncAt, fallback: .current),
            summary: self.summary(from: counts, fallback: "Notion crawl status is current"),
            configPath: self.stringValue(["config_path", "config"], in: object),
            databasePath: self.stringValue(["db_path", "database_path", "database"], in: object),
            databaseBytes: self.intValue(["db_bytes", "database_bytes"], in: object),
            walBytes: self.intValue(["wal_bytes"], in: object),
            lastSyncAt: lastSyncAt,
            counts: counts,
            freshness: self.freshness(lastSyncAt: lastSyncAt),
            share: self.shareStatus(in: object))
    }

    private func genericStatus(_ object: [String: Any], result: CrawlCommandResult) -> CrawlAppStatus {
        let counts = self.counts(in: object)
        let lastSyncAt = self.dateValue(["last_sync_at", "updated_at", "generated_at"], in: object)
        return CrawlAppStatus(
            appID: result.appID,
            state: self.state(lastSyncAt: lastSyncAt, fallback: .current),
            summary: self.stringValue(["summary", "message"], in: object) ?? self.summary(from: counts, fallback: "Status is current"),
            configPath: self.stringValue(["config_path"], in: object),
            databasePath: self.stringValue(["db_path", "database_path"], in: object),
            lastSyncAt: lastSyncAt,
            counts: counts,
            freshness: self.freshness(lastSyncAt: lastSyncAt),
            share: self.shareStatus(in: object))
    }

    private func failureSummary(_ result: CrawlCommandResult) -> String {
        let output = result.stderr.nilIfBlank ?? result.stdout.nilIfBlank
        return output?.split(separator: "\n").first.map(String.init) ?? "Command failed with exit \(result.exitCode)"
    }

    private func parseObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8), !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func count(_ id: String, _ label: String, _ keys: [String]) -> (String, String, [String]) {
        (id, label, keys)
    }

    private func value(_ spec: (String, String, [String]), in object: [String: Any]) -> CrawlCount? {
        guard let value = self.intValue(spec.2, in: object) else { return nil }
        return CrawlCount(id: spec.0, label: spec.1, value: value)
    }

    private func counts(in object: [String: Any]) -> [CrawlCount] {
        guard let counts = self.firstObject(["counts", "stats"], in: object) else { return [] }
        return counts.compactMap { key, value in
            guard let int = self.int(value) else { return nil }
            return CrawlCount(id: key, label: self.label(from: key), value: int)
        }
        .sorted { $0.id < $1.id }
    }

    private func state(lastSyncAt: Date?, fallback: CrawlAppState) -> CrawlAppState {
        guard let lastSyncAt else { return fallback }
        return Date().timeIntervalSince(lastSyncAt) > 86_400 ? .stale : .current
    }

    private func freshness(lastSyncAt: Date?, staleAfterSeconds: Int = 86_400) -> CrawlFreshness? {
        guard let lastSyncAt else { return nil }
        let ageSeconds = max(0, Int(Date().timeIntervalSince(lastSyncAt)))
        return CrawlFreshness(
            status: ageSeconds > staleAfterSeconds ? .stale : .current,
            ageSeconds: ageSeconds,
            staleAfterSeconds: staleAfterSeconds)
    }

    private func summary(from counts: [CrawlCount], fallback: String) -> String {
        let visible = counts.prefix(2).map { "\($0.value) \($0.label.lowercased())" }
        return visible.isEmpty ? fallback : visible.joined(separator: ", ")
    }

    private func intValue(_ keys: [String], in object: [String: Any]) -> Int? {
        for key in keys {
            if let value = self.firstValue(key, in: object), let int = self.int(value) {
                return int
            }
        }
        return nil
    }

    private func stringValue(_ keys: [String], in object: [String: Any]) -> String? {
        for key in keys {
            if let value = self.firstValue(key, in: object) as? String, let string = value.nilIfBlank {
                return string
            }
        }
        return nil
    }

    private func dateValue(_ keys: [String], in object: [String: Any]) -> Date? {
        for key in keys {
            guard let value = self.firstValue(key, in: object) else { continue }
            if let date = self.date(value) {
                return date
            }
        }
        return nil
    }

    private func shareStatus(in object: [String: Any]) -> CrawlShareStatus? {
        guard let share = self.firstObject(["share", "sharing", "published"], in: object) else { return nil }
        return CrawlShareStatus(
            enabled: (share["enabled"] as? Bool) ?? (share["repo_path"] != nil),
            repoPath: share["repo_path"] as? String,
            remote: share["remote"] as? String,
            branch: share["branch"] as? String,
            needsUpdate: share["needs_update"] as? Bool)
    }

    private func firstObject(_ keys: [String], in object: [String: Any]) -> [String: Any]? {
        for key in keys {
            if let object = self.firstValue(key, in: object) as? [String: Any] {
                return object
            }
        }
        return nil
    }

    private func firstValue(_ key: String, in object: [String: Any]) -> Any? {
        if let value = object[key] { return value }
        for value in object.values {
            if let nested = value as? [String: Any], let match = self.firstValue(key, in: nested) {
                return match
            }
        }
        return nil
    }

    private func int(_ value: Any) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func date(_ value: Any) -> Date? {
        if let date = value as? Date { return date }
        if let number = value as? NSNumber {
            let seconds = number.doubleValue > 99_999_999_999 ? number.doubleValue / 1_000 : number.doubleValue
            return Date(timeIntervalSince1970: seconds)
        }
        guard let string = value as? String, let trimmed = string.nilIfBlank else { return nil }
        if let date = ISO8601DateFormatter.crawlBarFormatter().date(from: trimmed) {
            return date
        }
        if let seconds = Double(trimmed) {
            return Date(timeIntervalSince1970: seconds > 99_999_999_999 ? seconds / 1_000 : seconds)
        }
        return nil
    }

    private func label(from key: String) -> String {
        key
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
