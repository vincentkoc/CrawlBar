# CrawlBar

CrawlBar is a macOS menu bar control plane for local-first `*crawl` apps.

It discovers crawler CLIs, reads metadata manifests, shows status/freshness/counts, runs refresh and doctor actions, writes redacted job logs, and keeps per-app config in `~/.crawlbar/config.json`.

## Apps

Built-in manifests ship for:

- `gitcrawl`
- `slacrawl`
- `discrawl`
- `notcrawl`

Future crawler repos can drop a manifest JSON file into `~/.crawlbar/apps/*.json` to appear without a CrawlBar code change.

## Build

```sh
swift build
swift run crawlbar-selftest
swift run crawlbar apps --json
```

## CLI

```sh
crawlbar apps [--json]
crawlbar metadata [--app gitcrawl] [--json]
crawlbar status [--app all] [--json]
crawlbar doctor --app discrawl [--json]
crawlbar refresh --app slacrawl [--json]
crawlbar action desktop-cache-import --app discrawl [--json]
crawlbar logs [--json]
crawlbar config path|validate|init
```

## Config

Main config lives at:

```text
~/.crawlbar/config.json
```

Action logs live at:

```text
~/.crawlbar/logs
```

Both are written with private file permissions. Command output is redacted before it is returned to the UI or persisted as an action log.

## Package The App

```sh
Scripts/package_app.sh
```

The packaged `.app` is written to `dist/CrawlBar.app`.
