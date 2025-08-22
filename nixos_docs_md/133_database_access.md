## Database access

Keycloak can be used with either PostgreSQL, MariaDB or MySQL. Which one is used can be configured in [`services.keycloak.database.type`](options.html#opt-services.keycloak.database.type). The selected database will automatically be enabled and a database and role created unless [`services.keycloak.database.host`](options.html#opt-services.keycloak.database.host) is changed from its default of `localhost` or [`services.keycloak.database.createLocally`](options.html#opt-services.keycloak.database.createLocally) is set to `false`.

External database access can also be configured by setting [`services.keycloak.database.host`](options.html#opt-services.keycloak.database.host), [`services.keycloak.database.name`](options.html#opt-services.keycloak.database.name), [`services.keycloak.database.username`](options.html#opt-services.keycloak.database.username), [`services.keycloak.database.useSSL`](options.html#opt-services.keycloak.database.useSSL) and [`services.keycloak.database.caCert`](options.html#opt-services.keycloak.database.caCert) as appropriate. Note that you need to manually create the database and allow the configured database user full access to it.

[`services.keycloak.database.passwordFile`](options.html#opt-services.keycloak.database.passwordFile) must be set to the path to a file containing the password used to log in to the database. If [`services.keycloak.database.host`](options.html#opt-services.keycloak.database.host) and [`services.keycloak.database.createLocally`](options.html#opt-services.keycloak.database.createLocally) are kept at their defaults, the database role `keycloak` with that password is provisioned on the local database instance.

### Warning

The path should be provided as a string, not a Nix path, since Nix paths are copied into the world readable Nix store.
