## General considerations on upgrades

Garage provides a cookbook documentation on how to upgrade: [https://garagehq.deuxfleurs.fr/documentation/cookbook/upgrading/](https://garagehq.deuxfleurs.fr/documentation/cookbook/upgrading/)

### Warning

Garage has two types of upgrades: patch-level upgrades and minor/major version upgrades.

In all cases, you should read the changelog and ideally test the upgrade on a staging cluster.

Checking the health of your cluster can be achieved using `garage-manage repair`.

- **Straightforward upgrades (patch-level upgrades).** Upgrades must be performed one by one, i.e. for each node, stop it, upgrade it : change [stateVersion](options.html#opt-system.stateVersion) or [services.garage.package](options.html#opt-services.garage.package), restart it if it was not already by switching.

- **Multiple version upgrades.** Garage do not provide any guarantee on moving more than one major-version forward. E.g., if you’re on `0.9`, you cannot upgrade to `2.0`. You need to upgrade to `1.2` first. As long as [stateVersion](options.html#opt-system.stateVersion) is declared properly, this is enforced automatically. The module will issue a warning to remind the user to upgrade to latest Garage _after_ that deploy.
