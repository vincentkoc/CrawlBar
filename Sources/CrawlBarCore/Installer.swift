import Foundation

public enum CrawlInstallerError: LocalizedError, Sendable {
    case installUnavailable(CrawlAppID)
    case brewUnavailable
    case unsupportedMethod(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case let .installUnavailable(appID):
            "\(appID.rawValue) does not declare an installer"
        case .brewUnavailable:
            "Homebrew is not available on PATH"
        case let .unsupportedMethod(method):
            "Unsupported install method: \(method)"
        case let .failed(message):
            message
        }
    }
}

public struct CrawlInstaller: @unchecked Sendable {
    private let resolver: CrawlExecutableResolver
    private let redactor: CrawlCommandRedactor

    public init(
        resolver: CrawlExecutableResolver = CrawlExecutableResolver(),
        redactor: CrawlCommandRedactor = CrawlCommandRedactor())
    {
        self.resolver = resolver
        self.redactor = redactor
    }

    public func install(_ installation: CrawlAppInstallation, timeoutSeconds: TimeInterval = 900) throws -> CrawlCommandResult {
        guard let install = installation.manifest.install else {
            throw CrawlInstallerError.installUnavailable(installation.id)
        }

        switch install.method {
        case .homebrew:
            guard let brewPath = self.resolver.resolve("brew") else {
                throw CrawlInstallerError.brewUnavailable
            }
            return try self.run(
                appID: installation.id,
                executablePath: brewPath,
                arguments: ["install", install.package],
                timeoutSeconds: timeoutSeconds)
        }
    }

    private func run(
        appID: CrawlAppID,
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval)
        throws -> CrawlCommandResult
    {
        let startedAt = Date()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let stdoutURL = tempDirectory.appendingPathComponent("stdout.log")
        let stderrURL = tempDirectory.appendingPathComponent("stderr.log")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        try process.run()
        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            process.terminate()
            process.waitUntilExit()
            throw CrawlCommandRunnerError.timedOut(appID: appID, action: "install", seconds: Int(timeoutSeconds))
        }

        try? stdoutHandle.synchronize()
        try? stderrHandle.synchronize()

        let stdout = try String(contentsOf: stdoutURL, encoding: .utf8)
        let stderr = try String(contentsOf: stderrURL, encoding: .utf8)
        let result = CrawlCommandResult(
            appID: appID,
            action: "install",
            exitCode: process.terminationStatus,
            stdout: self.redactor.redact(stdout),
            stderr: self.redactor.redact(stderr),
            startedAt: startedAt,
            finishedAt: Date())
        if result.exitCode != 0 {
            throw CrawlInstallerError.failed(result.stderr.nilIfBlank ?? result.stdout.nilIfBlank ?? "Install failed with exit \(result.exitCode)")
        }
        return result
    }
}
