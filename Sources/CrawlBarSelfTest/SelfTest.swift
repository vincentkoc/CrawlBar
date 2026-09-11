import CrawlBarCore
import Foundation

@main
enum CrawlBarSelfTest {
    static func main() throws {
        try Self.testNativeArchiveMappingAndBackupSelection()
        try Self.testNativeStatusFreshnessAndMissingState()
        try Self.testNativeRecursiveConfigExpansion()
        try Self.testActionAttemptCadenceAndShareRetry()
        try Self.testActionExclusionAndConsent()
        try Self.testActionSelectedArgumentsAndChangedConfig()
        try Self.testScheduledPublicationConsent()
        try Self.testExistingCredentialFixOnFailureLogs()
        if CommandLine.arguments.contains("--native-safety") {
            print("crawlbar synthetic native safety selftest ok")
            return
        }
        try Self.testAppIDSortsByRawValue()
        try Self.testDefaultConfigNormalizesBuiltInApps()
        try Self.testConfigStoreRoundTrips()
        try Self.testExternalManifestCatalog()
        try Self.testNativeConfigRoundTrips()
        try Self.testStatusSecretsLoadFromNativeConfig()
        try Self.testStatusMapperNormalizesCounts()
        try Self.testStatusMapperTrustsCrawlerState()
        try Self.testStatusMapperNormalizesWacliDoctorOutput()
        try Self.testStatusMapperNormalizesGogAuthStatus()
        try Self.testStatusMapperNormalizesBirdclawAuthStatus()
        try Self.testGogStatusServiceVerifiesOAuthOrServiceAccount()
        try Self.testActionFailuresPreserveStatusMetadata()
        try Self.testActionLogStoreReadsRecentResults()
        try Self.testQueryActionResolverSkipsSQLForPlainText()
        try Self.testExecutableResolverUsesMacCliFallbackPaths()
        try Self.testRegistryResolvesBirdclawAccessPathBinary()
        try Self.testConfigValuesReachCommandEnvironment()
        try Self.testRemoteSshExecutionBuildsCommand()
        try Self.testWacliSearchJoinsQueryArguments()
        try Self.testGitcrawlCommandArgumentsInferRepository()
        try Self.testCommandTimeoutEscalates()
        try Self.testProcessWaitTimesOut()
        try Self.testInstallerTimesOutWedgedBrew()
        try Self.testTimeoutTeardownUsesProcessWait()
        try Self.testDatabaseBackupCopiesFiles()
        try Self.testDatabaseBackupTimesOutWedgedSqlite()
        try Self.testRedactorScrubsSecrets()
        print("crawlbar selftest ok")
    }
}
