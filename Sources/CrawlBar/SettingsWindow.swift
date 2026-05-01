import AppKit
import CrawlBarCore
import SwiftUI

@MainActor
final class CrawlBarSettingsWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
            return
        }

        let model = CrawlBarSettingsModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "CrawlBar"
        window.toolbarStyle = .unified
        window.center()
        window.contentMinSize = NSSize(width: 660, height: 480)
        window.contentView = NSHostingView(rootView: CrawlBarSettingsView(model: model))
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        self.window = window
    }
}

@MainActor
final class CrawlBarSettingsModel: ObservableObject {
    @Published var apps: [CrawlBarAppConfig] = []
    @Published var refreshFrequency: RefreshFrequency = .fifteenMinutes
    @Published var selectedAppID: CrawlAppID?
    @Published var statuses: [CrawlAppID: CrawlAppStatus] = [:]
    @Published var installations: [CrawlAppID: CrawlAppInstallation] = [:]
    @Published var isRefreshing = false
    @Published var runningActions: [CrawlAppID: String] = [:]
    @Published var actionMessages: [CrawlAppID: String] = [:]
    @Published var lastError: String?

    private var manifestDirectories: [String] = ["~/.crawlbar/apps"]
    private let store = CrawlBarConfigStore()
    private let registry = CrawlAppRegistry()
    private let runner = CrawlCommandRunner()
    private let mapper = CrawlStatusMapper()
    private let logStore = CrawlActionLogStore()

    init() {
        self.load()
        self.refreshAll()
    }

    func load() {
        do {
            let config = try self.store.loadOrCreateDefault()
            let loadedInstallations = try self.registry.installations(includeDisabled: true)
            self.apps = config.apps
            self.refreshFrequency = config.refreshFrequency
            self.manifestDirectories = config.manifestDirectories
            self.installations = Dictionary(uniqueKeysWithValues: loadedInstallations.map { ($0.id, $0) })
            if self.selectedAppID == nil || !self.apps.contains(where: { $0.id == self.selectedAppID }) {
                self.selectedAppID = self.apps.first?.id
            }
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func save() {
        do {
            try self.store.save(CrawlBarConfig(
                refreshFrequency: self.refreshFrequency,
                manifestDirectories: self.manifestDirectories,
                apps: self.apps))
            self.load()
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func moveUp(_ id: CrawlAppID) {
        guard let index = self.apps.firstIndex(where: { $0.id == id }), index > 0 else { return }
        self.apps.swapAt(index, index - 1)
        self.save()
    }

    func moveDown(_ id: CrawlAppID) {
        guard let index = self.apps.firstIndex(where: { $0.id == id }), index < self.apps.count - 1 else { return }
        self.apps.swapAt(index, index + 1)
        self.save()
    }

    func refreshAll() {
        self.isRefreshing = true
        let registry = self.registry
        let runner = self.runner
        let mapper = self.mapper
        Task.detached {
            let installations = (try? registry.installations(includeDisabled: true)) ?? []
            await MainActor.run {
                self.installations = Dictionary(uniqueKeysWithValues: installations.map { ($0.id, $0) })
            }
            await withTaskGroup(of: CrawlAppStatus.self) { group in
                for installation in installations {
                    group.addTask {
                        Self.status(for: installation, runner: runner, mapper: mapper)
                    }
                }
                for await status in group {
                    await MainActor.run {
                        self.statuses[status.appID] = status
                    }
                }
            }
            await MainActor.run {
                self.isRefreshing = false
            }
        }
    }

    func runAction(_ action: String, appID: CrawlAppID) {
        guard let installation = self.installations[appID] else { return }
        self.runningActions[appID] = action
        self.actionMessages[appID] = "Running \(Self.actionTitle(action))..."
        let runner = self.runner
        let mapper = self.mapper
        let logStore = self.logStore
        Task.detached {
            let message: String
            do {
                let result = try runner.run(installation: installation, action: action, timeoutSeconds: 600)
                _ = try? logStore.save(result)
                message = result.exitCode == 0
                    ? "\(Self.actionTitle(action)) finished"
                    : "\(Self.actionTitle(action)) failed with exit \(result.exitCode)"
            } catch {
                message = error.localizedDescription
            }
            let status = Self.status(for: installation, runner: runner, mapper: mapper)
            await MainActor.run {
                self.statuses[appID] = status
                self.runningActions[appID] = nil
                self.actionMessages[appID] = message
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
            let result = try runner.run(installation: installation, action: "status", timeoutSeconds: 5)
            return mapper.status(from: result, manifest: installation.manifest)
        } catch CrawlCommandRunnerError.timedOut {
            return CrawlAppStatus(
                appID: installation.id,
                state: .unknown,
                summary: "Status check is slow; run Doctor for a full check")
        } catch {
            return CrawlAppStatus(appID: installation.id, state: .error, summary: error.localizedDescription, errors: [error.localizedDescription])
        }
    }

    nonisolated private static func actionTitle(_ action: String) -> String {
        switch action {
        case "refresh":
            "Sync"
        case "doctor":
            "Doctor"
        case "publish":
            "Publish"
        case "update":
            "Update"
        default:
            action
        }
    }
}

struct CrawlBarSettingsView: View {
    @ObservedObject var model: CrawlBarSettingsModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            self.sidebar
            self.detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 700, height: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Crawlers")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    self.model.refreshAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Refresh status")
                Button {
                    NSWorkspace.shared.open(CrawlActionLogStore.defaultDirectory())
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Open logs")
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(self.model.apps) { app in
                        CrawlBarSidebarRow(
                            app: app,
                            manifest: self.model.installations[app.id]?.manifest,
                            status: self.model.statuses[app.id],
                            binaryPath: self.model.installations[app.id]?.binaryPath)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    self.model.selectedAppID == app.id
                                        ? Color(nsColor: .selectedContentBackgroundColor)
                                        : Color.clear)
                                .padding(.horizontal, 4))
                        .contentShape(Rectangle())
                        .onTapGesture { self.model.selectedAppID = app.id }
                    }
                }
                .padding(.vertical, 4)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Text("Default Sync")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Picker("Default Sync", selection: self.$model.refreshFrequency) {
                    ForEach(RefreshFrequency.allCases, id: \.self) { frequency in
                        Text(CrawlBarFrequencyLabel.text(for: frequency)).tag(frequency)
                    }
                }
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 118)
                .onChange(of: self.model.refreshFrequency) {
                    self.model.save()
                }
            }

            if let error = self.model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 236)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedID = self.model.selectedAppID,
           let index = self.model.apps.firstIndex(where: { $0.id == selectedID })
        {
            CrawlBarAppDetailView(
                app: self.binding(for: index),
                globalRefreshFrequency: self.model.refreshFrequency,
                installation: self.model.installations[selectedID],
                status: self.model.statuses[selectedID],
                isRefreshing: self.model.isRefreshing,
                runningAction: self.model.runningActions[selectedID],
                actionMessage: self.model.actionMessages[selectedID],
                moveUp: { self.model.moveUp(selectedID) },
                moveDown: { self.model.moveDown(selectedID) },
                refreshStatus: { self.model.refreshAll() },
                runAction: { action in self.model.runAction(action, appID: selectedID) },
                save: { self.model.save() })
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Select a crawler")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for index: Int) -> Binding<CrawlBarAppConfig> {
        Binding(
            get: { self.model.apps[index] },
            set: {
                self.model.apps[index] = $0
                self.model.save()
            })
    }
}

struct CrawlBarSidebarRow: View {
    let app: CrawlBarAppConfig
    let manifest: CrawlAppManifest?
    let status: CrawlAppStatus?
    let binaryPath: String?

    var body: some View {
        HStack(spacing: 11) {
            CrawlBarBrandIcon(manifest: self.manifest, appID: self.app.id)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(self.manifest?.displayName ?? self.app.id.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    CrawlBarStatusDot(state: self.rowState)
                }
                Text(self.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    private var rowState: CrawlAppState {
        if !self.app.enabled { return .disabled }
        if self.binaryPath == nil { return .needsConfig }
        return self.status?.state ?? .unknown
    }

    private var subtitle: String {
        if !self.app.enabled { return "Disabled" }
        if self.binaryPath == nil { return "Missing binary" }
        if let lastSyncAt = self.status?.lastSyncAt {
            return "Synced \(CrawlBarDateText.relative(lastSyncAt))"
        }
        return self.status?.summary ?? "Waiting for status"
    }
}

struct CrawlBarAppDetailView: View {
    @Binding var app: CrawlBarAppConfig
    let globalRefreshFrequency: RefreshFrequency
    let installation: CrawlAppInstallation?
    let status: CrawlAppStatus?
    let isRefreshing: Bool
    let runningAction: String?
    let actionMessage: String?
    let moveUp: () -> Void
    let moveDown: () -> Void
    let refreshStatus: () -> Void
    let runAction: (String) -> Void
    let save: () -> Void

    private var manifest: CrawlAppManifest? { self.installation?.manifest ?? BuiltInCrawlApps.manifest(for: self.app.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                self.header
                self.statusSummary
                Divider()
                self.metrics
                Divider()
                self.syncSettings
                Divider()
                self.gitShareSettings
                Divider()
                self.paths
                Divider()
                self.privacy
            }
            .frame(maxWidth: 430, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            CrawlBarBrandIcon(manifest: self.manifest, appID: self.app.id)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(self.manifest?.displayName ?? self.app.id.rawValue)
                        .font(.title3.weight(.semibold))
                    CrawlBarStatusPill(state: self.effectiveState)
                }
                Text(self.manifest?.description ?? self.app.id.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Button(action: self.refreshStatus) {
                    Image(systemName: self.isRefreshing ? "hourglass" : "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh status")
                Button(action: self.moveUp) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .help("Move up")
                Button(action: self.moveDown) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .help("Move down")
            }
            .controlSize(.small)
        }
    }

    private var statusSummary: some View {
        CrawlBarPanel {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    CrawlBarFact(label: "Status", value: self.status?.summary ?? self.statusFallback)
                    CrawlBarFact(label: "Last Sync", value: self.status?.lastSyncAt.map(CrawlBarDateText.relative) ?? "Never")
                }
                GridRow {
                    CrawlBarFact(
                        label: "Database",
                        value: self.status?.databasePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown")
                    CrawlBarFact(label: "Binary", value: self.installation?.binaryPath == nil ? "Missing" : "Found")
                }
            }
        }
    }

    @ViewBuilder
    private var metrics: some View {
        if let counts = self.status?.counts, !counts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Data")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                    ForEach(counts) { count in
                        CrawlBarMetricTile(label: count.label, value: "\(count.value)")
                    }
                }
            }
        }
    }

    private var syncSettings: some View {
        CrawlBarPanel(title: "Sync") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enabled", isOn: self.$app.enabled)
                    .onChange(of: self.app.enabled) { self.save() }
                Toggle("Show in menu bar", isOn: self.$app.showInMenuBar)
                    .onChange(of: self.app.showInMenuBar) { self.save() }
                Toggle("Automatic sync", isOn: self.$app.autoRefreshEnabled)
                    .onChange(of: self.app.autoRefreshEnabled) { self.save() }
                Toggle("Use default schedule", isOn: self.usesGlobalRefreshBinding)
                    .disabled(!self.app.autoRefreshEnabled)
            }
            Picker("Sync every", selection: self.refreshFrequencyBinding) {
                ForEach(RefreshFrequency.allCases, id: \.self) { frequency in
                    Text(CrawlBarFrequencyLabel.text(for: frequency)).tag(frequency)
                }
            }
            .disabled(!self.app.autoRefreshEnabled || self.app.refreshFrequency == nil)
            .controlSize(.small)
            Text("Global sync schedule: \(CrawlBarFrequencyLabel.text(for: self.globalRefreshFrequency))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if self.commandAvailable(self.app.preferredRefreshAction ?? "refresh") {
                    Button {
                        self.runAction(self.app.preferredRefreshAction ?? "refresh")
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                if self.commandAvailable("doctor") {
                    Button {
                        self.runAction("doctor")
                    } label: {
                        Label("Doctor", systemImage: "stethoscope")
                    }
                }
                if self.commandAvailable(self.app.preferredUpdateAction ?? "update") {
                    Button {
                        self.runAction(self.app.preferredUpdateAction ?? "update")
                    } label: {
                        Label("Update", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .disabled(self.runningAction != nil)
            if let runningAction {
                Label("Running \(runningAction)...", systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gitShareSettings: some View {
        CrawlBarPanel(title: "Git Share") {
            Toggle("Manage Git snapshot for this crawler", isOn: self.$app.shareEnabled)
                .onChange(of: self.app.shareEnabled) { self.save() }
            Toggle("Publish after refresh", isOn: self.$app.shareAfterRefresh)
                .disabled(!self.app.shareEnabled)
                .onChange(of: self.app.shareAfterRefresh) { self.save() }
            HStack(spacing: 8) {
                if self.commandAvailable(self.app.preferredShareAction ?? "publish") {
                    Button("Publish") { self.runAction(self.app.preferredShareAction ?? "publish") }
                }
                if self.commandAvailable(self.app.preferredUpdateAction ?? "update") {
                    Button("Pull Updates") { self.runAction(self.app.preferredUpdateAction ?? "update") }
                }
            }
            .disabled(!self.app.shareEnabled || self.runningAction != nil)
            Divider()
            CrawlBarFact(label: "Share Repo", value: self.status?.share?.repoPath ?? self.manifest?.paths.defaultShare ?? "Not configured")
            CrawlBarFact(label: "Remote", value: self.status?.share?.remote ?? "Unknown")
            CrawlBarFact(label: "Branch", value: self.status?.share?.branch ?? "Unknown")
        }
    }

    private var paths: some View {
        CrawlBarPanel(title: "Paths") {
            TextField("Binary path override", text: self.optionalText(\.binaryPath))
                .textFieldStyle(.roundedBorder)
            TextField("Config path override", text: self.optionalText(\.configPath))
                .textFieldStyle(.roundedBorder)
            CrawlBarFact(label: "Default Config", value: self.manifest?.paths.defaultConfig ?? "None")
            CrawlBarFact(label: "Default Database", value: self.status?.databasePath ?? self.manifest?.paths.defaultDatabase ?? "Unknown")
            CrawlBarFact(label: "Logs", value: self.manifest?.paths.defaultLogs ?? "Unknown")
        }
    }

    private var privacy: some View {
        CrawlBarPanel(title: "Privacy") {
            CrawlBarFact(
                label: "Private Messages",
                value: self.manifest?.privacy.containsPrivateMessages == true ? "Possible local data" : "Not declared")
            CrawlBarFact(label: "Local-only scopes", value: self.manifest?.privacy.localOnlyScopes.joined(separator: ", ").nilIfBlank ?? "None")
            CrawlBarFact(label: "Action logs", value: CrawlActionLogStore.defaultDirectory().path)
        }
    }

    private var effectiveState: CrawlAppState {
        if !self.app.enabled { return .disabled }
        if self.installation?.binaryPath == nil { return .needsConfig }
        return self.status?.state ?? .unknown
    }

    private var statusFallback: String {
        switch self.effectiveState {
        case .needsConfig:
            "\(self.manifest?.binary.name ?? self.app.id.rawValue) is not on PATH"
        case .disabled:
            "Disabled in CrawlBar"
        default:
            "Waiting for status"
        }
    }

    private var usesGlobalRefreshBinding: Binding<Bool> {
        Binding(
            get: { self.app.refreshFrequency == nil },
            set: {
                self.app.refreshFrequency = $0 ? nil : self.globalRefreshFrequency
                self.save()
            })
    }

    private var refreshFrequencyBinding: Binding<RefreshFrequency> {
        Binding(
            get: { self.app.refreshFrequency ?? self.globalRefreshFrequency },
            set: {
                self.app.refreshFrequency = $0
                self.save()
            })
    }

    private func commandAvailable(_ action: String) -> Bool {
        self.manifest?.commands[action] != nil && self.installation?.binaryPath != nil && self.app.enabled
    }

    private func optionalText(_ keyPath: WritableKeyPath<CrawlBarAppConfig, String?>) -> Binding<String> {
        Binding(
            get: { self.app[keyPath: keyPath] ?? "" },
            set: {
                self.app[keyPath: keyPath] = $0.nilIfBlank
                self.save()
            })
    }
}

struct CrawlBarPanel<Content: View>: View {
    var title: String?
    var caption: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                self.content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CrawlBarStatusDot: View {
    let state: CrawlAppState

    var body: some View {
        Circle()
            .fill(self.color)
            .frame(width: 8, height: 8)
            .help(self.state.rawValue)
    }

    private var color: Color {
        switch self.state {
        case .current:
            .green
        case .stale, .unknown:
            .yellow
        case .syncing:
            .blue
        case .needsConfig, .needsAuth, .error:
            .red
        case .disabled:
            .gray
        }
    }
}

struct CrawlBarStatusPill: View {
    let state: CrawlAppState

    var body: some View {
        HStack(spacing: 5) {
            CrawlBarStatusDot(state: self.state)
            Text(self.state.rawValue.replacingOccurrences(of: "_", with: " "))
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.12))
        .clipShape(Capsule())
    }
}

struct CrawlBarFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(self.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(self.value)
                .font(.callout)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CrawlBarMetricTile: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(self.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(self.value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum CrawlBarFrequencyLabel {
    static func text(for frequency: RefreshFrequency) -> String {
        switch frequency {
        case .manual:
            "Manual"
        case .fiveMinutes:
            "5 minutes"
        case .fifteenMinutes:
            "15 minutes"
        case .thirtyMinutes:
            "30 minutes"
        case .hourly:
            "Hourly"
        }
    }
}

enum CrawlBarDateText {
    @MainActor
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
