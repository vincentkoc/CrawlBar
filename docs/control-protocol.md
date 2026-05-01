# CrawlBar Control Protocol

CrawlBar treats each crawler as a local CLI with a small control contract.

## Manifest

A crawler can be built in or represented by a manifest JSON file under `~/.crawlbar/apps`.

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

## Actions

Actions are manifest command arrays. CrawlBar does not shell-expand them.

- `status` should be fast and read-only.
- `doctor` may inspect auth/config and should avoid writes unless the crawler already defines that behavior.
- `refresh` may pull data into the local database.
- `publish`, `update`, and exporter actions are optional and should return JSON when possible.

## Privacy

Command output is redacted before display or persistence. Logs are stored under `~/.crawlbar/logs` with private permissions.

Crawler authors should still avoid printing raw tokens, cookies, authorization headers, session IDs, or desktop cache secrets.
