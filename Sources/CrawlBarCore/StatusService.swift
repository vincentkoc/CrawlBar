import Foundation

public struct CrawlStatusService: @unchecked Sendable {
    private let runner: CrawlCommandRunner
    private let mapper: CrawlStatusMapper

    public init(
        runner: CrawlCommandRunner = CrawlCommandRunner(),
        mapper: CrawlStatusMapper = CrawlStatusMapper())
    {
        self.runner = runner
        self.mapper = mapper
    }

    public func status(for installation: CrawlAppInstallation, timeoutSeconds: TimeInterval = 30) -> CrawlAppStatus {
        guard installation.manifest.availability == .available else {
            return CrawlAppStatus(appID: installation.id, state: .disabled, summary: "Coming soon")
        }
        guard installation.enabled else {
            return CrawlAppStatus(appID: installation.id, state: .disabled, summary: "Disabled in CrawlBar config")
        }
        guard installation.binaryPath != nil else {
            return CrawlAppStatus(appID: installation.id, state: .needsConfig, summary: "\(installation.manifest.binary.name) is not on PATH")
        }
        if let status = GitcrawlStatusSnapshot.status(for: installation) {
            return status
        }
        do {
            let result = try self.runner.run(installation: installation, action: "status", timeoutSeconds: timeoutSeconds)
            return self.mapper.status(from: result, manifest: installation.manifest)
        } catch CrawlCommandRunnerError.timedOut {
            return CrawlAppStatus(
                appID: installation.id,
                state: .unknown,
                summary: "Status check is slow; run Doctor for a full check")
        } catch {
            return CrawlAppStatus(appID: installation.id, state: .error, summary: error.localizedDescription, errors: [error.localizedDescription])
        }
    }
}
