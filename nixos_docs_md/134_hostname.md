## Hostname

The hostname is used to build the public URL used as base for all frontend requests and must be configured through [`services.keycloak.settings.hostname`](options.html#opt-services.keycloak.settings.hostname).

### Note

If you’re migrating an old Wildfly based Keycloak instance and want to keep compatibility with your current clients, you’ll likely want to set [`services.keycloak.settings.http-relative-path`](options.html#opt-services.keycloak.settings.http-relative-path) to `/auth`. See the option description for more details.

[`services.keycloak.settings.hostname-backchannel-dynamic`](options.html#opt-services.keycloak.settings.hostname-backchannel-dynamic) Keycloak has the capability to offer a separate URL for backchannel requests, enabling internal communication while maintaining the use of a public URL for frontchannel requests. Moreover, the backchannel is dynamically resolved based on incoming headers endpoint.

For more information on hostname configuration, see the [Hostname section of the Keycloak Server Installation and Configuration Guide](https://www.keycloak.org/server/hostname).
