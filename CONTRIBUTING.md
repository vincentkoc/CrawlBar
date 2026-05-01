# Contributing

Keep changes small and prove the touched surface.

## Checks

```sh
swift build
swift run crawlbar-selftest
swift run crawlbarctl apps --json
```

Use `swift run crawlbarctl status --app all --json` only when you expect local crawler CLIs to be installed. It should not require live databases to exist.

## Manifest Changes

Prefer manifest metadata over hard-coded UI branches. Built-in manifests belong in `Sources/CrawlBarCore/BuiltInCrawlApps.swift`; app-specific parsing belongs in `StatusMapper.swift`.

External manifest examples should use fake paths and no real tokens.

## Privacy

Never add fixtures with real API keys, Discord tokens, Slack cookies, Notion session values, or authorization headers. If a command result is persisted, it must pass through `CrawlCommandRedactor`.
