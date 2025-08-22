## Using the Mattermost derivation

The nixpkgs `mattermost` derivation runs the entire test suite during the `checkPhase`. This test suite is run with a live MySQL and Postgres database instance in the sandbox. If you are building Mattermost, this can take a while, especially if it is building on a resource-constrained system.

The following passthrus are designed to assist with enabling or disabling the `checkPhase`:

- `mattermost.withTests`

- `mattermost.withoutTests`

The default (`mattermost`) is an alias for `mattermost.withTests`.
