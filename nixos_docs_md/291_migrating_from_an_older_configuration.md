## Migrating from an older configuration

With Mautrix-Signal v0.7.0 the configuration has been rearranged. Mautrix-Signal performs an automatic configuration migration so your pre-0.7.0 configuration should just continue to work.

In case you want to update your NixOS configuration, compare the migrated configuration at `/var/lib/mautrix-signal/config.yaml` with the default configuration (`nix-shell -p mautrix-signal --run "mautrix-signal -c example.yaml -e"`) and update your module configuration accordingly.
