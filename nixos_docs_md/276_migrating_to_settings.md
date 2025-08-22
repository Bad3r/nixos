## Migrating to settings

Migrating a cluster to the new `settings`-based changes requires adapting removed options to the corresponding upstream settings.

This means that the upstream [Broker Configs documentation](https://kafka.apache.org/documentation/#brokerconfigs) should be followed closely.

Note that dotted options in the upstream docs do _not_ correspond to nested Nix attrsets, but instead as quoted top level `settings` attributes, as in `services.apache-kafka.settings."broker.id"`, _NOT_ `services.apache-kafka.settings.broker.id`.

Care should be taken, especially when migrating clusters from the old module, to ensure that the same intended configuration is reproduced faithfully via `settings`.

To assist in the comparison, the final config can be inspected by building the config file itself, ie. with: `nix-build <nixpkgs/nixos> -A config.services.apache-kafka.configFiles.serverProperties`.

Notable changes to be aware of include:

- Removal of `services.apache-kafka.extraProperties` and `services.apache-kafka.serverProperties`
  - Translate using arbitrary properties using [`services.apache-kafka.settings`](options.html#opt-services.apache-kafka.settings)

  - [Upstream docs](https://kafka.apache.org/documentation.html#brokerconfigs)

  - The intention is for all broker properties to be fully representable via [`services.apache-kafka.settings`](options.html#opt-services.apache-kafka.settings).

  - If this is not the case, please do consider raising an issue.

  - Until it can be remedied, you _can_ bail out by using [`services.apache-kafka.configFiles.serverProperties`](options.html#opt-services.apache-kafka.configFiles.serverProperties) to the path of a fully rendered properties file.

- Removal of `services.apache-kafka.hostname` and `services.apache-kafka.port`
  - Translate using: `services.apache-kafka.settings.listeners`

  - [Upstream docs](https://kafka.apache.org/documentation.html#brokerconfigs_listeners)

- Removal of `services.apache-kafka.logDirs`
  - Translate using: `services.apache-kafka.settings."log.dirs"`

  - [Upstream docs](https://kafka.apache.org/documentation.html#brokerconfigs_log.dirs)

- Removal of `services.apache-kafka.brokerId`
  - Translate using: `services.apache-kafka.settings."broker.id"`

  - [Upstream docs](https://kafka.apache.org/documentation.html#brokerconfigs_broker.id)

- Removal of `services.apache-kafka.zookeeper`
  - Translate using: `services.apache-kafka.settings."zookeeper.connect"`

  - [Upstream docs](https://kafka.apache.org/documentation.html#brokerconfigs_zookeeper.connect)
