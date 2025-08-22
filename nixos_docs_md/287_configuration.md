## Configuration

1.  Set [`services.mautrix-whatsapp.enable`](options.html#opt-services.mautrix-whatsapp.enable) to `true`. The service will use SQLite by default.

2.  To create your configuration check the default configuration for [`services.mautrix-whatsapp.settings`](options.html#opt-services.mautrix-whatsapp.settings). To obtain the complete default configuration, run `nix-shell -p mautrix-whatsapp --run "mautrix-whatsapp -c default.yaml -e"`.

### Warning

Mautrix-Whatsapp allows for some options like `encryption.pickle_key`, `provisioning.shared_secret`, allow the value `generate` to be set. Since the configuration file is regenerated on every start of the service, the generated values would be discarded and might break your installation. Instead, set those values via [`services.mautrix-whatsapp.environmentFile`](options.html#opt-services.mautrix-whatsapp.environmentFile).
