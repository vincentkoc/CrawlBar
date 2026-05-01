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
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "CrawlBar Settings"
        window.center()
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
    @Published var lastError: String?

    private let store = CrawlBarConfigStore()

    init() {
        self.load()
    }

    func load() {
        do {
            let config = try self.store.loadOrCreateDefault()
            self.apps = config.apps
            self.refreshFrequency = config.refreshFrequency
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func save() {
        do {
            try self.store.save(CrawlBarConfig(refreshFrequency: self.refreshFrequency, apps: self.apps))
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func moveUp(_ index: Int) {
        guard index > 0 else { return }
        self.apps.swapAt(index, index - 1)
        self.save()
    }

    func moveDown(_ index: Int) {
        guard index < self.apps.count - 1 else { return }
        self.apps.swapAt(index, index + 1)
        self.save()
    }
}

struct CrawlBarSettingsView: View {
    @ObservedObject var model: CrawlBarSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("CrawlBar")
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker("Refresh", selection: self.$model.refreshFrequency) {
                    ForEach(RefreshFrequency.allCases, id: \.self) { frequency in
                        Text(self.label(for: frequency)).tag(frequency)
                    }
                }
                .frame(width: 220)
                .onChange(of: self.model.refreshFrequency) {
                    self.model.save()
                }
            }

            List {
                ForEach(self.model.apps.indices, id: \.self) { index in
                    let app = self.model.apps[index]
                    CrawlBarSettingsAppRow(
                        app: self.binding(for: index),
                        manifest: BuiltInCrawlApps.manifest(for: app.id),
                        moveUp: { self.model.moveUp(index) },
                        moveDown: { self.model.moveDown(index) },
                        save: { self.model.save() })
                }
            }
            .listStyle(.inset)

            if let lastError = self.model.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
    }

    private func binding(for index: Int) -> Binding<CrawlBarAppConfig> {
        Binding(
            get: { self.model.apps[index] },
            set: {
                self.model.apps[index] = $0
                self.model.save()
            })
    }

    private func label(for frequency: RefreshFrequency) -> String {
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

struct CrawlBarSettingsAppRow: View {
    @Binding var app: CrawlBarAppConfig
    let manifest: CrawlAppManifest?
    let moveUp: () -> Void
    let moveDown: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Toggle("", isOn: self.$app.enabled)
                    .labelsHidden()
                    .onChange(of: self.app.enabled) { self.save() }
                Image(systemName: self.manifest?.branding.symbolName ?? "terminal")
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.manifest?.displayName ?? self.app.id.rawValue)
                        .font(.headline)
                    Text(self.manifest?.description ?? self.app.id.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: self.moveUp) {
                    Image(systemName: "arrow.up")
                }
                Button(action: self.moveDown) {
                    Image(systemName: "arrow.down")
                }
            }

            HStack(spacing: 10) {
                TextField("Binary path override", text: self.optionalText(\.binaryPath))
                TextField("Config path override", text: self.optionalText(\.configPath))
            }
            .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 8)
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
