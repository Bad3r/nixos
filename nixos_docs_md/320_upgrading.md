## Upgrading

Usually, TigerBeetle’s [upgrade process](https://docs.tigerbeetle.com/operating/upgrading) only requires replacing the binary used for the servers. This is not directly possible with NixOS since the new binary will be located at a different place in the Nix store.

However, since TigerBeetle is managed through systemd on NixOS, the only action you need to take when upgrading is to make sure the version of TigerBeetle you’re upgrading to supports upgrades from the version you’re currently running. This information will be on the [release notes](https://github.com/tigerbeetle/tigerbeetle/releases) for the version you’re upgrading to.
