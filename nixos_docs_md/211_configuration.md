## Configuration

The Mosquitto configuration has four distinct types of settings: the global settings of the daemon, listeners, plugins, and bridges. Bridges and listeners are part of the global configuration, plugins are part of listeners. Users of the broker are configured as parts of listeners rather than globally, allowing configurations in which a given user is only allowed to log in to the broker using specific listeners (eg to configure an admin user with full access to all topics, but restricted to localhost).

Almost all options of Mosquitto are available for configuration at their appropriate levels, some as NixOS options written in camel case, the remainders under `settings` with their exact names in the Mosquitto config file. The exceptions are `acl_file` (which is always set according to the `acl` attributes of a listener and its users) and `per_listener_settings` (which is always set to `true`).

### Password authentication

Mosquitto can be run in two modes, with a password file or without. Each listener has its own password file, and different listeners may use different password files. Password file generation can be disabled by setting `omitPasswordAuth = true` for a listener; in this case it is necessary to either set `settings.allow_anonymous = true` to allow all logins, or to configure other authentication methods like TLS client certificates with `settings.use_identity_as_username = true`.

The default is to generate a password file for each listener from the users configured to that listener. Users with no configured password will not be added to the password file and thus will not be able to use the broker.

### ACL format

Every listener has a Mosquitto `acl_file` attached to it. This ACL is configured via two attributes of the config:

- the `acl` attribute of the listener configures pattern ACL entries and topic ACL entries for anonymous users. Each entry must be prefixed with `pattern` or `topic` to distinguish between these two cases.

- the `acl` attribute of every user configures in the listener configured the ACL for that given user. Only topic ACLs are supported by Mosquitto in this setting, so no prefix is required or allowed.

The default ACL for a listener is empty, disallowing all accesses from all clients. To configure a completely open ACL, set `acl = [ "pattern readwrite #" ]` in the listener.
