## Configuration

1.  Set [`services.mautrix-signal.enable`](options.html#opt-services.mautrix-signal.enable) to `true`. The service will use SQLite by default.

2.  To create your configuration check the default configuration for [`services.mautrix-signal.settings`](options.html#opt-services.mautrix-signal.settings). To obtain the complete default configuration, run `nix-shell -p mautrix-signal --run "mautrix-signal -c default.yaml -e"`.

### Warning

Mautrix-Signal allows for some options like `encryption.pickle_key`, `provisioning.shared_secret`, allow the value `generate` to be set. Since the configuration file is regenerated on every start of the service, the generated values would be discarded and might break your installation. Instead, set those values via [`services.mautrix-signal.environmentFile`](options.html#opt-services.mautrix-signal.environmentFile).
