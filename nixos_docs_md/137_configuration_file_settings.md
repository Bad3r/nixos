## Configuration file settings

Keycloak server configuration parameters can be set in [`services.keycloak.settings`](options.html#opt-services.keycloak.settings). These correspond directly to options in `conf/keycloak.conf`. Some of the most important parameters are documented as suboptions, the rest can be found in the [All configuration section of the Keycloak Server Installation and Configuration Guide](https://www.keycloak.org/server/all-config).

Options containing secret data should be set to an attribute set containing the attribute `_secret` - a string pointing to a file containing the value the option should be set to. See the description of [`services.keycloak.settings`](options.html#opt-services.keycloak.settings) for an example.
