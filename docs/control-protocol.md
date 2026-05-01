# CrawlBar Control Protocol

CrawlBar treats each crawler as a local CLI with a small control contract.
Today that contract lives in CrawlBar manifests and adapters. The cleaner
long-term home is `crawlkit`, because the Go CLIs already share config,
status, output, desktop-cache, pack, and git-share infrastructure there.

## Manifest

A crawler can be built in or represented by a manifest JSON file under
`~/.crawlbar/apps`. Once `crawlkit` grows a control package, each crawler should
also expose the same payload through `metadata --json`.

```json
{
  "schema_version": 1,
  "id": "examplecrawl",
  "display_name": "Example Crawl",
  "description": "Local archive for Example",
  "binary": { "name": "examplecrawl" },
  "branding": { "symbol_name": "tray", "accent_color": "#2F81F7" },
  "paths": {
    "default_config": "~/.examplecrawl/config.toml",
    "config_env": "EXAMPLECRAWL_CONFIG",
    "default_database": "~/.examplecrawl/examplecrawl.db",
    "default_logs": "~/.examplecrawl/logs",
    "default_share": "~/.examplecrawl/share"
  },
  "commands": {
    "metadata": ["metadata", "--json"],
    "status": ["status", "--json"],
    "doctor": ["doctor", "--json"],
    "refresh": ["sync", "--json"],
    "publish": ["publish", "--json"],
    "update": ["update", "--json"]
  },
  "capabilities": ["status", "doctor", "refresh", "publish", "update"],
  "privacy": {
    "contains_private_messages": false,
    "exports_secrets": false,
    "local_only_scopes": []
  }
}
```

## Status Output

CrawlBar accepts varied JSON, then normalizes known fields into one status model:

- `*_count`, `counts`, or `stats` become menu counters.
- `last_sync_at`, `last_import_at`, `updated_at`, or epoch values become freshness.
- `db_path`, `database_path`, `db_bytes`, and `wal_bytes` become storage metadata.
- `share` or `sharing` becomes share/export state.

Unknown fields are allowed. The app should not break when a crawler adds extra data.

The preferred future shape is a `crawlkit`-owned status envelope with:

- `app_id`, `schema_version`, `generated_at`, `state`, and `summary`.
- normalized counters as `{id,label,value}` rows.
- effective config/database/cache/log/share paths from `configkit`.
- freshness from `syncstate`.
- share/export state from `gitshare` and `pack`.
- warnings/errors with no secret values.

## Actions

Actions are manifest command arrays. CrawlBar does not shell-expand them.

- `status` should be fast and read-only.
- `doctor` may inspect auth/config and should avoid writes unless the crawler already defines that behavior.
- `refresh` may pull data into the local database.
- `publish`, `update`, and exporter actions are optional and should return JSON when possible.
- desktop-cache actions should use public names such as `desktopcache` or `tap`.
  Existing `wiretap` command names can stay as backward-compatible aliases, but
  new metadata should not advertise `wiretap`.

## Privacy

Command output is redacted before display or persistence. Logs are stored under `~/.crawlbar/logs` with private permissions.

Crawler authors should still avoid printing raw tokens, cookies, authorization headers, session IDs, or desktop cache secrets.
