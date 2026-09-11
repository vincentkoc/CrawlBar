# Changelog

## v0.4.2 - Unreleased

### Fixes

- Recheck scheduled publication consent without the main-config cache, including pending retries, while preserving unchanged native-only settings.
- Map iMessage archive paths without exposing the Messages source database to backup selection.
- Keep status check timestamps separate from import/sync freshness and recognize missing external archives as requiring setup.
- Preserve recursive configuration substitution while bounding cycles and expansion.
- Coordinate manual and scheduled mutations per crawler, respect retry intervals after failed attempts, and retry failed publication without repeating successful sync.
- Apply both share consent settings to manual sync publication and discard superseded action status updates.
- Allow Settings sync to publish with unchanged native configuration, while stopping automatic publication when consent or nonsecret configuration changes or the main config is missing or invalid.
- Re-read the main config before automatic publication so external consent, destination or malformed-file changes cannot be hidden by a cached modification time.
- Stop automatic publication and scheduled publication retries when native config-only values change or their selected local config becomes unreadable, even if saved Settings values mask the change.
- Check the native configuration selected by the command environment before automatic publication; refuse an empty configuration-file selector without changing manually invoked commands.
- Restore legacy data `updated_at` as a freshness fallback without treating status-generation time as fresh data.
- Keep crawler credentials out of UI/CLI installation state and redact echoed credentials before command output or action-log persistence. Thanks @vincentkoc.
- Bound crawler-command and Homebrew-install timeout teardown so actions return when process termination fails. Thanks @SebTardif.
- Bound SQLite backup process waits to 600 seconds so wedged backups return a timeout instead of hanging Settings or the CLI. Thanks @SebTardif.

## v0.4.1 - 2026-07-09

### Changes

- Distribute notarized universal macOS builds signed by the OpenClaw Foundation, including Homebrew installs, so the app identity persists across upgrades.

### Fixes

- Accept current `crawlkit/control` manifests when optional descriptions or branding metadata are omitted.

## v0.4.0 - 2026-06-19

### Changes

- Add iMessage as a built-in crawler with status, refresh, search, privacy metadata, and native Messages branding.
- Add Apple Photos as a coming-soon built-in crawler with read-only status, initialization, search, and platform-native storage paths.
- Add development binary registration commands for testing local crawler builds in CrawlBar.

### Fixes

- Install OpenClaw crawler apps from the current Homebrew tap instead of legacy formulas that lag released versions.

## v0.3.0 - 2026-06-09

### Changes

- Redesign the menu bar UI with RepoBar-style native rich menu rows, branded crawler icons, status summaries, and tabbed settings.
- Replace crawler detail tabs in Settings with one native scrolling detail page grouped into status, data, sync, and configuration sections.
- Improve app responsiveness by caching repeated config, manifest, binary lookup, native app, formatter, and icon work while reducing status refresh task overhead.
- Open Settings immediately by moving manifest, binary, config, and recent-log loading off the main actor.
- Use native switch-style controls for crawler boolean settings.
- Replace the generated app icon with a richer image-generated CrawlBar icon and use it for both runtime and packaged app icons.
- Enable Google (`gog`) and WhatsApp (`wacli`) crawler entries with real status, doctor, search, and install wiring.
- Fix Settings sidebar clicks so selecting crawler rows reliably updates the detail pane, and show the active sidebar selection clearly.
- Normalize crawler command environments with `HOME` so launchd-started menu bar status matches terminal status for tools like `gog`.
- Add Telecrawl as a built-in Telegram crawler with status, import, doctor, search, privacy, install metadata, and branded menu icon support.
- Add Weicrawl as a built-in Weixin/WeChat crawler with status, desktop snapshot import, unlock status, search, export, privacy, install metadata, and native WeChat icon support.
- Make menu and settings opening faster by caching rendered crawler icons, coalescing status menu rebuilds, and avoiding synchronous refresh work during settings presentation.
- Add CrawlBar support for Cloudflare remote crawler archives, including built-in `remote status`, `remote archives`, and compressed SQLite `cloud publish` actions for `gitcrawl` and `discrawl`.
- Surface Cloudflare D1/R2 archive status, remote archive metadata, and gzip chunked SQLite bundle details in normalized status JSON and the settings UI.
- Bundle real macOS app icons for GitHub Desktop, Slack, Discord, Notion, WhatsApp, and Granola crawler rows.
- Guard source and packaged brand icon assets in CI so crawler logos cannot regress silently. Thanks @vincentkoc.

## v0.2.2 - 2026-05-22

### Fixes

- Fix crawler discovery from the macOS app by normalizing PATH with common Homebrew, MacPorts, and user-local CLI locations before resolving or running crawler commands. Thanks @mbelinky.

## v0.2.1 - 2026-05-22

### Fixes

- Fix packaged app icon loading by resolving the SwiftPM resource bundle from installed app locations and failing packaging when the bundle is missing or empty. Thanks @mbelinky.

## v0.2.0 - 2026-05-20

### Changes

- Add the native CrawlBar menu bar app for local-first crawler status, refreshes, logs, settings, and packaged CLI access.
- Add built-in crawler manifests for GitHub, Slack, Discord, Notion, and Granola, with coming-soon entries for Google, WhatsApp, and X.
- Add branded crawler icons, including bundled Google, X, and Granola assets for offline app/package rendering.
- Add crawler detail tabs for Overview, Data, Sync, and Settings, with refresh, archive, binary, snapshot, and config state shown where relevant.
- Add local app packaging through `Scripts/package_app.sh`, including the `CrawlBar.app` bundle and embedded `crawlbar` helper.
- Add Homebrew source-build support for installing the app bundle and CLI together.

### Fixes

- Avoid macOS Keychain prompts during read-only status paths.
- Preserve native crawler secret semantics while still allowing CrawlBar-managed secrets to be cleared explicitly.
- Keep all-app query behavior searchable and route SQL/text queries to the right crawler capability.
- Surface crawler action failures instead of hiding them behind stale successful state.
- Normalize GitHub authentication failures as credential problems instead of raw request errors.
- Preserve useful current crawler data when refreshes fail.
- Hide successful exit-0 stdout noise in the latest-run summary.
- Remove window-level tooltips from the main app while keeping menu bar affordances usable.
- Hide empty snapshot remote details and avoid duplicating Data summaries in Overview.
- Show remote crawler stores for GitHub-backed archives.
- Write numeric crawler config values as numbers, fixing Graincrawl desktop-cache recovery after cache-version failures.

### Maintenance

- Add SwiftPM CI covering build, selftest, CLI smoke, app packaging, and packaged CLI smoke.
- Add a selftest suite for config normalization, metadata mapping, crawler failure semantics, query routing, and settings behavior.
- Add the control protocol documentation and example manifest for future crawler integrations.

## v0.1.0

- Initial local CrawlBar prototype.
