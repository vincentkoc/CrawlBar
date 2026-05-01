import Foundation

public enum CrawlCommandRunnerError: LocalizedError, Sendable {
    case executableNotFound(String)
    case commandUnavailable(appID: CrawlAppID, action: String)
    case timedOut(appID: CrawlAppID, action: String, seconds: Int)

    public var errorDescription: String? {
        switch self {
        case let .executableNotFound(name):
            "Could not find executable: \(name)"
        case let .commandUnavailable(appID, action):
            "\(appID.rawValue) does not expose a \(action) command"
        case let .timedOut(appID, action, seconds):
            "\(appID.rawValue) \(action) timed out after \(seconds)s"
        }
    }
}

public struct CrawlCommandRedactor: Sendable {
    public init() {}

    public func redact(_ text: String) -> String {
        var redacted = text
        let patterns: [(String, String)] = [
            (#"(?i)(Bearer\s+)[^\s"',}]+"#, "$1[REDACTED]"),
            (#"(?i)(api[_-]?key|token|secret|password|cookie|authorization)(["'\s:=]+)([^\s"',}]+)"#, "$1$2[REDACTED]"),
            (#"(?i)(xox[baprs]-)[A-Za-z0-9-]+"#, "$1[REDACTED]"),
            (#"(?i)(discord(?:_token)?["'\s:=]+)([^\s"',}]+)"#, "$1[REDACTED]"),
        ]
        for (pattern, template) in patterns {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: template,
                options: [.regularExpression])
        }
        return redacted
    }
}

public struct CrawlExecutableResolver: @unchecked Sendable {
    private let fileManager: FileManager
    private let environment: [String: String]

    public init(fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.fileManager = fileManager
        self.environment = environment
    }

    public func resolve(_ requestedPathOrName: String) -> String? {
        let expanded = PathExpander.expandHome(requestedPathOrName)
        if expanded.contains("/") {
            return self.isExecutable(expanded) ? expanded : nil
        }

        let pathEntries = (self.environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)

        for entry in pathEntries {
            let candidate = URL(fileURLWithPath: entry)
                .appendingPathComponent(expanded)
                .path
            if self.isExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func isExecutable(_ path: String) -> Bool {
        self.fileManager.isExecutableFile(atPath: path)
    }
}

public struct CrawlCommandRunner: @unchecked Sendable {
    private let resolver: CrawlExecutableResolver
    private let redactor: CrawlCommandRedactor
    private let fileManager: FileManager
    private let environment: [String: String]

    public init(
        resolver: CrawlExecutableResolver = CrawlExecutableResolver(),
        redactor: CrawlCommandRedactor = CrawlCommandRedactor(),
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment)
    {
        self.resolver = resolver
        self.redactor = redactor
        self.fileManager = fileManager
        self.environment = environment
    }

    public func run(
        installation: CrawlAppInstallation,
        action: String,
        timeoutSeconds: TimeInterval = 120)
        throws -> CrawlCommandResult
    {
        guard let arguments = installation.manifest.commands[action] else {
            throw CrawlCommandRunnerError.commandUnavailable(appID: installation.id, action: action)
        }

        let executableName = installation.binaryPath ?? installation.manifest.binary.name
        guard let executablePath = self.resolver.resolve(executableName) else {
            throw CrawlCommandRunnerError.executableNotFound(executableName)
        }

        var commandEnvironment = self.environment
        if let envName = installation.manifest.paths.configEnv,
           let configPath = installation.configPathOverride?.nilIfBlank
        {
            commandEnvironment[envName] = PathExpander.expandHome(configPath)
        }

        return try self.runProcess(
            appID: installation.id,
            action: action,
            executablePath: executablePath,
            arguments: arguments,
            environment: commandEnvironment,
            timeoutSeconds: timeoutSeconds)
    }

    private func runProcess(
        appID: CrawlAppID,
        action: String,
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: TimeInterval)
        throws -> CrawlCommandResult
    {
        let startedAt = Date()
        let tempDirectory = self.fileManager.temporaryDirectory
            .appendingPathComponent("crawlbar-\(UUID().uuidString)", isDirectory: true)
        try self.fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? self.fileManager.removeItem(at: tempDirectory) }

        let stdoutURL = tempDirectory.appendingPathComponent("stdout.log")
        let stderrURL = tempDirectory.appendingPathComponent("stderr.log")
        self.fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        self.fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        try process.run()
        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            process.terminate()
            process.waitUntilExit()
            throw CrawlCommandRunnerError.timedOut(
                appID: appID,
                action: action,
                seconds: Int(timeoutSeconds))
        }

        try? stdoutHandle.synchronize()
        try? stderrHandle.synchronize()

        let stdout = try String(contentsOf: stdoutURL, encoding: .utf8)
        let stderr = try String(contentsOf: stderrURL, encoding: .utf8)
        return CrawlCommandResult(
            appID: appID,
            action: action,
            exitCode: process.terminationStatus,
            stdout: self.redactor.redact(stdout),
            stderr: self.redactor.redact(stderr),
            startedAt: startedAt,
            finishedAt: Date())
    }
}
