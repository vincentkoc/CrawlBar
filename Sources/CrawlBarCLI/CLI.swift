import CrawlBarCore
import Foundation

@main
enum CrawlBarCLI {
    static func main() {
        do {
            try Self.run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            CLIOutput.writeError(error.localizedDescription)
            Foundation.exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else {
            Self.printHelp()
            return
        }

        let options = CLIOptions(arguments.dropFirst())
        let registry = CrawlAppRegistry()
        let runner = CrawlCommandRunner()
        let mapper = CrawlStatusMapper()

        switch command {
        case "apps":
            try Self.printApps(registry: registry, json: options.json)
        case "logs":
            try Self.printLogs(json: options.json)
        case "metadata":
            try Self.printMetadata(registry: registry, appID: options.appID, json: options.json)
        case "status":
            try Self.printStatus(registry: registry, runner: runner, mapper: mapper, options: options)
        case "doctor", "refresh":
            try Self.runAction(command, registry: registry, runner: runner, json: options.json, appID: options.requiredAppID())
        case "action":
            guard let action = options.positionals.first else {
                throw CLIError.usage("action requires an action id")
            }
            try Self.runAction(action, registry: registry, runner: runner, json: options.json, appID: options.requiredAppID())
        case "config":
            try Self.runConfig(options)
        case "help", "--help", "-h":
            Self.printHelp()
        default:
            throw CLIError.usage("unknown command: \(command)")
        }
    }

    private static func printApps(registry: CrawlAppRegistry, json: Bool) throws {
        let apps = try registry.installations(includeDisabled: true).map(CLIApp.init)
        if json {
            try CLIOutput.writeJSON(apps)
            return
        }
        for app in apps {
            let marker = app.enabled ? (app.available ? "ok" : "missing") : "disabled"
            print("\(marker)\t\(app.id)\t\(app.displayName)")
        }
    }

    private static func printMetadata(registry: CrawlAppRegistry, appID: CrawlAppID?, json: Bool) throws {
        let installations = try registry.installations(includeDisabled: true)
        let manifests = installations
            .filter { appID == nil || $0.id == appID }
            .map(\.manifest)
        if json {
            try CLIOutput.writeJSON(manifests)
            return
        }
        for manifest in manifests {
            print("\(manifest.id.rawValue)\t\(manifest.displayName)\t\(manifest.binary.name)")
        }
    }

    private static func printLogs(json: Bool) throws {
        let logs = CrawlActionLogStore().recent(limit: 50).map { $0.path }
        if json {
            try CLIOutput.writeJSON(logs)
            return
        }
        logs.forEach { print($0) }
    }

    private static func printStatus(
        registry: CrawlAppRegistry,
        runner: CrawlCommandRunner,
        mapper: CrawlStatusMapper,
        options: CLIOptions)
        throws
    {
        let requestedID = options.appID
        let installations = try registry.installations(includeDisabled: true)
            .filter { requestedID == nil || requestedID == CrawlAppID(rawValue: "all") || $0.id == requestedID }
        let statuses = installations.map { installation -> CrawlAppStatus in
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

        if options.json {
            try CLIOutput.writeJSON(statuses)
            return
        }
        for status in statuses {
            print("\(status.state.rawValue)\t\(status.appID.rawValue)\t\(status.summary)")
        }
    }

    private static func runAction(
        _ action: String,
        registry: CrawlAppRegistry,
        runner: CrawlCommandRunner,
        json: Bool,
        appID: CrawlAppID)
        throws
    {
        guard let installation = try registry.installation(for: appID) else {
            throw CLIError.usage("unknown app: \(appID.rawValue)")
        }
        guard installation.enabled else {
            throw CLIError.usage("\(appID.rawValue) is disabled")
        }
        guard installation.binaryPath != nil else {
            throw CLIError.usage("\(installation.manifest.binary.name) is not on PATH")
        }
        let result = try runner.run(installation: installation, action: action, timeoutSeconds: 600)
        _ = try? CrawlActionLogStore().save(result)
        if json {
            try CLIOutput.writeJSON(result)
            return
        }
        print(result.stdout.nilIfBlank ?? result.stderr.nilIfBlank ?? "exit \(result.exitCode)")
        if !result.succeeded {
            Foundation.exit(Int32(result.exitCode))
        }
    }

    private static func runConfig(_ options: CLIOptions) throws {
        let store = CrawlBarConfigStore()
        switch options.positionals.first {
        case "path":
            print(store.fileURL.path)
        case "validate":
            _ = try store.loadOrCreateDefault()
            print("ok")
        case "init", nil:
            let config = try store.loadOrCreateDefault()
            try CLIOutput.writeJSON(config)
        case let command?:
            throw CLIError.usage("unknown config command: \(command)")
        }
    }

    private static func printHelp() {
        print("""
        crawlbar commands:
          apps [--json]
          logs [--json]
          metadata [--app <id>] [--json]
          status [--app <id|all>] [--json]
          doctor --app <id> [--json]
          refresh --app <id> [--json]
          action <action-id> --app <id> [--json]
          config path|validate|init
        """)
    }
}

private struct CLIApp: Encodable {
    var id: String
    var displayName: String
    var enabled: Bool
    var available: Bool
    var binaryPath: String?
    var configPath: String?

    init(_ installation: CrawlAppInstallation) {
        self.id = installation.id.rawValue
        self.displayName = installation.manifest.displayName
        self.enabled = installation.enabled
        self.available = installation.binaryPath != nil
        self.binaryPath = installation.binaryPath
        self.configPath = installation.configPathOverride
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case enabled
        case available
        case binaryPath = "binary_path"
        case configPath = "config_path"
    }
}

private struct CLIOptions {
    var json = false
    var appID: CrawlAppID?
    var positionals: [String] = []

    init(_ arguments: ArraySlice<String>) {
        var iterator = Array(arguments).makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--json":
                self.json = true
            case "--app":
                if let value = iterator.next() {
                    self.appID = CrawlAppID(rawValue: value)
                }
            default:
                self.positionals.append(argument)
            }
        }
    }

    func requiredAppID() throws -> CrawlAppID {
        guard let appID else {
            throw CLIError.usage("--app <id> is required")
        }
        return appID
    }
}

private enum CLIError: LocalizedError {
    case usage(String)

    var errorDescription: String? {
        switch self {
        case let .usage(message):
            message
        }
    }
}
