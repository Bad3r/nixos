## Defaults

- The default nixos package doesn’t come with the [dashboard](https://docs.meilisearch.com/learn/getting_started/quick_start.html#search), since the dashboard features makes some assets downloads at compile time.

- `no_analytics` is set to true by default.

- `http_addr` is derived from `services.meilisearch.listenAddress` and `services.meilisearch.listenPort`. The two sub-fields are separate because this makes it easier to consume in certain other modules.

- `db_path` is set to `/var/lib/meilisearch` by default. Upstream, the default value is equivalent to `/var/lib/meilisearch/data.ms`.

- `dump_dir` and `snapshot_dir` are set to `/var/lib/meilisearch/dumps` and `/var/lib/meilisearch/snapshots`, respectively. This is equivalent to the upstream defaults.

- All other options inherit their upstream defaults. In particular, the default configuration uses `env = "development"`, which doesn’t require a master key, in which case all routes are unprotected.
