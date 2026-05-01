import AppKit
import CrawlBarCore

@main
@MainActor
enum CrawlBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = CrawlBarAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class CrawlBarAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private let settingsWindowController = CrawlBarSettingsWindowController()
    private let model = CrawlBarMenuModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = CrawlBarIconFactory.menuBarImage()
        statusItem.button?.imagePosition = .imageLeading
        self.statusItem = statusItem
        self.reloadMenu()
        self.model.refreshAll { [weak self] in
            self?.reloadMenu()
        }
        self.scheduleRefreshTimer()
    }

    private func reloadMenu() {
        let menu = NSMenu()
        let title = self.model.isRefreshing ? "Refreshing..." : "Refresh All"
        menu.addItem(NSMenuItem(title: title, action: #selector(Self.refreshAll(_:)), keyEquivalent: "r", target: self))
        menu.addItem(.separator())

        for installation in self.model.visibleInstallations {
            let config = self.model.appConfig(for: installation.id)
            let status = self.model.statuses[installation.id]
            let state = status?.state.rawValue ?? (installation.binaryPath == nil ? "missing" : "unknown")
            let summary = status?.summary ?? installation.manifest.description
            let appItem = NSMenuItem(title: "\(installation.manifest.displayName): \(state)", action: nil, keyEquivalent: "")
            appItem.image = CrawlBarIconFactory.image(for: installation.id, manifest: installation.manifest, size: 18)
            appItem.toolTip = summary
            menu.addItem(appItem)

            if installation.enabled, installation.binaryPath != nil {
                menu.addItem(self.actionItem("  Sync", appID: installation.id, action: config?.preferredRefreshAction ?? "refresh"))
                menu.addItem(self.actionItem("  Doctor", appID: installation.id, action: "doctor"))
                if config?.shareEnabled == true {
                    menu.addItem(self.actionItem("  Publish", appID: installation.id, action: config?.preferredShareAction ?? "publish"))
                    menu.addItem(self.actionItem("  Pull Updates", appID: installation.id, action: config?.preferredUpdateAction ?? "update"))
                }
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Logs", action: #selector(Self.openLogs(_:)), keyEquivalent: "l", target: self))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(Self.showSettings(_:)), keyEquivalent: ",", target: self))
        menu.addItem(NSMenuItem(title: "Quit CrawlBar", action: #selector(Self.quit(_:)), keyEquivalent: "q", target: self))
        self.statusItem?.menu = menu
    }

    private func actionItem(_ title: String, appID: CrawlAppID, action: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(Self.runAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = CrawlMenuCommand(appID: appID, action: action)
        return item
    }

    private func scheduleRefreshTimer() {
        self.refreshTimer?.invalidate()
        self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.model.runDueAutoSync {
                    self?.reloadMenu()
                }
            }
        }
    }

    @objc private func refreshAll(_ sender: Any?) {
        self.model.refreshAll { [weak self] in
            self?.reloadMenu()
        }
        self.reloadMenu()
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? CrawlMenuCommand else { return }
        self.model.run(command: command) { [weak self] in
            self?.reloadMenu()
        }
        self.reloadMenu()
    }

    @objc private func showSettings(_ sender: Any?) {
        self.settingsWindowController.show()
        self.model.reloadInstallations()
        self.scheduleRefreshTimer()
        self.reloadMenu()
    }

    @objc private func openLogs(_ sender: Any?) {
        NSWorkspace.shared.open(CrawlActionLogStore.defaultDirectory())
    }

    @objc private func quit(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }
}

final class CrawlMenuCommand: NSObject {
    let appID: CrawlAppID
    let action: String

    init(appID: CrawlAppID, action: String) {
        self.appID = appID
        self.action = action
    }
}

@MainActor
final class CrawlBarMenuModel {
    private let registry = CrawlAppRegistry()
    private let runner = CrawlCommandRunner()
    private let mapper = CrawlStatusMapper()
    private let logStore = CrawlActionLogStore()

    var installations: [CrawlAppInstallation] = []
    var statuses: [CrawlAppID: CrawlAppStatus] = [:]
    var isRefreshing = false
    var refreshFrequency: RefreshFrequency = .fifteenMinutes
    private var appConfigs: [CrawlAppID: CrawlBarAppConfig] = [:]
    private var lastAutoSyncByAppID: [CrawlAppID: Date] = [:]

    init() {
        self.reloadInstallations()
    }

    var visibleInstallations: [CrawlAppInstallation] {
        self.installations.filter { installation in
            self.appConfigs[installation.id]?.showInMenuBar ?? true
        }
    }

    func appConfig(for id: CrawlAppID) -> CrawlBarAppConfig? {
        self.appConfigs[id]
    }

    func reloadInstallations() {
        if let config = try? self.registry.loadConfig() {
            self.refreshFrequency = config.refreshFrequency
            self.appConfigs = Dictionary(uniqueKeysWithValues: config.apps.map { ($0.id, $0) })
        }
        self.installations = (try? self.registry.installations(includeDisabled: true)) ?? []
    }

    func refreshAll(onComplete: @escaping @MainActor () -> Void) {
        self.isRefreshing = true
        let registry = self.registry
        let runner = self.runner
        let mapper = self.mapper
        Task.detached {
            let installations = (try? registry.installations(includeDisabled: true)) ?? []
            let statuses = installations.map { installation -> CrawlAppStatus in
                Self.status(for: installation, runner: runner, mapper: mapper)
            }
            await MainActor.run {
                self.installations = installations
                self.statuses = Dictionary(uniqueKeysWithValues: statuses.map { ($0.appID, $0) })
                self.isRefreshing = false
                onComplete()
            }
        }
    }

    func run(command: CrawlMenuCommand, onComplete: @escaping @MainActor () -> Void) {
        self.isRefreshing = true
        let appID = command.appID
        let action = command.action
        let registry = self.registry
        let runner = self.runner
        let mapper = self.mapper
        let logStore = self.logStore
        Task.detached {
            let installation = try? registry.installation(for: appID)
            if let installation {
                if let result = try? runner.run(installation: installation, action: action, timeoutSeconds: 600) {
                    _ = try? logStore.save(result)
                }
            }
            let refreshed = installation.map { Self.status(for: $0, runner: runner, mapper: mapper) }
            await MainActor.run {
                if let refreshed {
                    self.statuses[refreshed.appID] = refreshed
                }
                self.isRefreshing = false
                onComplete()
            }
        }
    }

    func runDueAutoSync(onComplete: @escaping @MainActor () -> Void) {
        guard !self.isRefreshing else { return }
        self.reloadInstallations()
        let now = Date()
        let dueInstallations = self.installations.filter { installation in
            guard let config = self.appConfigs[installation.id], config.enabled, config.autoRefreshEnabled else { return false }
            guard installation.enabled, installation.binaryPath != nil else { return false }
            guard let seconds = (config.refreshFrequency ?? self.refreshFrequency).seconds else { return false }
            let last = self.lastAutoSyncByAppID[installation.id] ?? .distantPast
            return now.timeIntervalSince(last) >= seconds
        }
        guard !dueInstallations.isEmpty else { return }

        self.isRefreshing = true
        let configs = self.appConfigs
        let runner = self.runner
        let mapper = self.mapper
        let logStore = self.logStore
        Task.detached {
            let statuses = dueInstallations.map { installation -> CrawlAppStatus in
                if let config = configs[installation.id] {
                    let refreshAction = config.preferredRefreshAction ?? "refresh"
                    if let result = try? runner.run(installation: installation, action: refreshAction, timeoutSeconds: 600) {
                        _ = try? logStore.save(result)
                    }
                    if config.shareEnabled, config.shareAfterRefresh {
                        let shareAction = config.preferredShareAction ?? "publish"
                        if let result = try? runner.run(installation: installation, action: shareAction, timeoutSeconds: 600) {
                            _ = try? logStore.save(result)
                        }
                    }
                }
                return Self.status(for: installation, runner: runner, mapper: mapper)
            }
            await MainActor.run {
                for status in statuses {
                    self.statuses[status.appID] = status
                    self.lastAutoSyncByAppID[status.appID] = now
                }
                self.isRefreshing = false
                onComplete()
            }
        }
    }

    nonisolated private static func status(
        for installation: CrawlAppInstallation,
        runner: CrawlCommandRunner,
        mapper: CrawlStatusMapper)
        -> CrawlAppStatus
    {
        guard installation.enabled else {
            return CrawlAppStatus(appID: installation.id, state: .disabled, summary: "Disabled in CrawlBar config")
        }
        guard installation.binaryPath != nil else {
            return CrawlAppStatus(appID: installation.id, state: .needsConfig, summary: "\(installation.manifest.binary.name) is not on PATH")
        }
        do {
            let result = try runner.run(installation: installation, action: "status", timeoutSeconds: 30)
            return mapper.status(from: result, manifest: installation.manifest)
        } catch {
            return CrawlAppStatus(appID: installation.id, state: .error, summary: error.localizedDescription, errors: [error.localizedDescription])
        }
    }
}

private extension NSMenuItem {
    convenience init(title: String, action: Selector?, keyEquivalent: String, target: AnyObject) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = target
    }
}
