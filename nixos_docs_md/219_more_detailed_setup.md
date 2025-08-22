## More detailed setup

The `firefox-syncserver` service provides a number of options to make setting up small deployment easier. These are grouped under the `singleNode` element of the option tree and allow simple configuration of the most important parameters.

Single node setup is split into two kinds of options: those that affect the sync server itself, and those that affect its surroundings. Options that affect the sync server are `capacity`, which configures how many accounts may be active on this instance, and `url`, which holds the URL under which the sync server can be accessed. The `url` can be configured automatically when using nginx.

Options that affect the surroundings of the sync server are `enableNginx`, `enableTLS` and `hostname`. If `enableNginx` is set the sync server module will automatically add an nginx virtual host to the system using `hostname` as the domain and set `url` accordingly. If `enableTLS` is set the module will also enable ACME certificates on the new virtual host and force all connections to be made via TLS.

For actual deployment it is also recommended to store the `secrets` file in a secure location.
