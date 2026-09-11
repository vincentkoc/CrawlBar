import CrawlBarCore
import Foundation

private struct CrawlActionStatusUpdate: Sendable {
    let status: CrawlAppStatus
    let actionFailure: CrawlAppStatus?
    let generation: UInt64
}

@MainActor
final class CrawlBarMenuModel: NSObject {
    private let registry = CrawlAppRegistry()
    private let runner: CrawlCommandRunner
    private let statusService: CrawlStatusService
    private let logStore = CrawlActionLogStore()

    var installations: [CrawlAppInstallation] = []
    var statuses: [CrawlAppID: CrawlAppStatus] = [:]
    var isRefreshing = false
    var refreshFrequency: RefreshFrequency = .fifteenMinutes
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = UUID()
    private var appConfigs: [CrawlAppID: CrawlBarAppConfig] = [:]

    override init() {
        let runner = CrawlCommandRunner()
        self.runner = runner
        self.statusService = CrawlStatusService(runner: runner)
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(Self.statusesDidChange(_:)),
            name: .crawlBarStatusesDidChange,
            object: nil)
        self.reloadInstallations()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var myMenuInstallations: [CrawlAppInstallation] {
        self.installations.filter { installation in
            guard installation.manifest.availability == .available else { return false }
            guard let config = self.appConfigs[installation.id] else { return false }
            guard config.enabled, config.showInMenuBar else { return false }
            return CrawlBarCrawlerClassifier.isMyCrawler(app: config, installation: installation)
        }
    }

    var suggestedMenuInstallations: [CrawlAppInstallation] {
        self.installations.filter { installation in
            guard installation.manifest.availability == .available else { return false }
            guard let config = self.appConfigs[installation.id] else { return false }
            guard config.enabled, config.showInMenuBar else { return false }
            return CrawlBarCrawlerClassifier.category(app: config, installation: installation) == .suggested
        }
    }

    var moreCrawlerCount: Int {
        self.installations.filter { installation in
            guard let config = self.appConfigs[installation.id] else { return false }
            return CrawlBarCrawlerClassifier.category(app: config, installation: installation) == .more
        }.count
    }

    var statusTargetInstallations: [CrawlAppInstallation] {
        CrawlBarCrawlerClassifier.statusInstallations(
            self.installations,
            appConfigsByID: self.appConfigs)
    }

    func appConfig(for id: CrawlAppID) -> CrawlBarAppConfig? {
        self.appConfigs[id]
    }

    func reloadInstallations() {
        if let config = try? self.registry.loadConfig() {
            self.refreshFrequency = config.refreshFrequency
            self.appConfigs = Dictionary(uniqueKeysWithValues: config.apps.map { ($0.id, $0) })
        } else {
            CrawlBarLog.config.error("Failed to load CrawlBar config")
        }
        self.installations = (try? self.registry.installations(includeDisabled: true)) ?? []
    }

    func refreshAll(onComplete: @escaping @MainActor () -> Void) {
        self.refreshTask?.cancel()
        let generation = UUID()
        self.refreshGeneration = generation
        self.isRefreshing = true
        let registry = self.registry
        let statusService = self.statusService
        let appConfigs = self.appConfigs
        self.refreshTask = Task.detached {
            let installations = (try? registry.installations(includeDisabled: true)) ?? []
            let statusInstallations = CrawlBarCrawlerClassifier.statusInstallations(
                installations,
                appConfigsByID: appConfigs)
            await MainActor.run {
                guard self.refreshGeneration == generation else { return }
                self.installations = installations
                onComplete()
            }
            let partitioned = Self.partitionStatuses(installations: statusInstallations, statusService: statusService)
            if !partitioned.immediate.isEmpty {
                await MainActor.run {
                    guard self.refreshGeneration == generation else { return }
                    for status in partitioned.immediate {
                        self.statuses[status.appID] = status
                    }
                    CrawlBarStateBroadcast.statusesDidChange(Dictionary(uniqueKeysWithValues: partitioned.immediate.map { ($0.appID, $0) }))
                    onComplete()
                }
            }
            await withTaskGroup(of: CrawlAppStatus.self) { group in
                for installation in partitioned.commandInstallations {
                    group.addTask {
                        guard !Task.isCancelled else {
                            return CrawlAppStatus(appID: installation.id, state: .unknown, summary: "Refresh cancelled")
                        }
                        return statusService.status(
                            for: installation,
                            configValues: registry.statusConfigValues(for: installation),
                            timeoutSeconds: 5)
                    }
                }
                for await status in group {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        guard self.refreshGeneration == generation else { return }
                        self.statuses[status.appID] = status
                        CrawlBarStateBroadcast.statusesDidChange([status.appID: status])
                        onComplete()
                    }
                }
            }
            await MainActor.run {
                guard self.refreshGeneration == generation else { return }
                self.isRefreshing = false
                self.refreshTask = nil
                onComplete()
            }
        }
    }

    func runDueAutoSync(onComplete: @escaping @MainActor () -> Void) {
        self.reloadInstallations()
        let now = Date()
        let dueInstallations = self.installations.filter { installation in
            guard let config = self.appConfigs[installation.id], config.enabled, config.autoRefreshEnabled else { return false }
            guard installation.enabled, installation.binaryPath != nil else { return false }
            guard let seconds = (config.refreshFrequency ?? self.refreshFrequency).seconds else { return false }
            return CrawlActionCoordinator.shared.isDue(installation.id, interval: seconds, now: now)
        }
        guard !dueInstallations.isEmpty else { return }

        let configs = self.appConfigs
        let refreshFrequency = self.refreshFrequency
        let registry = self.registry
        let runner = self.runner
        let statusService = self.statusService
        let logStore = self.logStore
        for installation in dueInstallations {
            Task.detached {
                let update = { () -> CrawlActionStatusUpdate? in
                    let actionConfigValues = registry.executionConfigValues(for: installation)
                    let nativePublicationGuard = registry.nativePublicationGuard(for: installation, configValues: actionConfigValues, runner: runner)
                    let statusConfigValues = registry.statusConfigValues(for: installation)
                    guard let config = configs[installation.id] else { return nil }
                    let outcome: CrawlActionOutcome
                    do {
                        outcome = try CrawlActionCoordinator.shared.run(
                            installation: installation,
                            config: config,
                            configValues: actionConfigValues,
                            action: config.preferredRefreshAction ?? "refresh",
                            scheduledInterval: (config.refreshFrequency ?? refreshFrequency).seconds,
                            allowShare: {
                                registry.matchesPersistedRawAppConfig(config)
                                    && nativePublicationGuard()
                            },
                            execute: { action in
                                try runner.run(
                                    installation: installation, configValues: actionConfigValues,
                                    action: action, timeoutSeconds: 600)
                            })
                    } catch CrawlActionCoordinatorError.busy, CrawlActionCoordinatorError.notDue {
                        return nil
                    } catch {
                        CrawlBarLog.actions.error("Scheduled action could not start: \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                    for result in outcome.results { _ = try? logStore.save(result) }
                    return CrawlActionStatusUpdate(
                        status: statusService.status(
                            for: installation,
                            configValues: statusConfigValues,
                            timeoutSeconds: 5),
                        actionFailure: outcome.failure,
                        generation: outcome.generation)
                }()
                guard let update else { return }
                await MainActor.run {
                    guard CrawlActionCoordinator.shared.isCurrent(update.status.appID, generation: update.generation) else { return }
                    let status = update.actionFailure.map {
                        Self.actionFailureStatus($0, refreshedStatus: update.status, currentStatus: self.statuses[$0.appID])
                    } ?? update.status
                    self.statuses[status.appID] = status
                    CrawlBarStateBroadcast.statusesDidChange([status.appID: status])
                    onComplete()
                }
            }
        }
    }

    private func mergeStatuses(_ incoming: [CrawlAppID: CrawlAppStatus]) {
        for (appID, status) in incoming {
            self.statuses[appID] = status
        }
    }

    @objc private func statusesDidChange(_ notification: Notification) {
        guard let statuses = CrawlBarStateBroadcast.statuses(from: notification) else { return }
        self.mergeStatuses(statuses)
    }

    nonisolated private static func partitionStatuses(
        installations: [CrawlAppInstallation],
        statusService: CrawlStatusService)
        -> (immediate: [CrawlAppStatus], commandInstallations: [CrawlAppInstallation])
    {
        var immediate: [CrawlAppStatus] = []
        var commandInstallations: [CrawlAppInstallation] = []
        for installation in installations {
            if let status = statusService.immediateStatus(for: installation) {
                immediate.append(status)
            } else {
                commandInstallations.append(installation)
            }
        }
        return (immediate, commandInstallations)
    }

    nonisolated private static func actionFailureStatus(_ result: CrawlCommandResult) -> CrawlAppStatus {
        let fallback = "\(result.action) failed with exit \(result.exitCode)"
        return CrawlAppStatus.commandFailure(
            appID: result.appID,
            action: result.action,
            message: result.stderr.nilIfBlank ?? result.stdout.nilIfBlank,
            fallback: fallback)
    }

    nonisolated private static func actionFailureStatus(appID: CrawlAppID, action: String, message: String) -> CrawlAppStatus {
        CrawlAppStatus.commandFailure(
            appID: appID,
            action: action,
            message: message,
            fallback: "\(action) failed")
    }

    nonisolated private static func actionFailureStatus(
        _ failure: CrawlAppStatus,
        refreshedStatus: CrawlAppStatus?,
        currentStatus: CrawlAppStatus?)
        -> CrawlAppStatus
    {
        guard let metadataStatus = CrawlAppStatus.richestMetadataStatus(refreshedStatus, fallback: currentStatus) else {
            return failure
        }
        return metadataStatus.mergingActionFailure(failure)
    }
}
