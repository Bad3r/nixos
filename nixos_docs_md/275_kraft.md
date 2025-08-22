## KRaft

Unlike in Zookeeper mode, Kafka in [KRaft](https://kafka.apache.org/documentation/#kraft) mode requires each log dir to be “formatted” (which means a cluster-specific a metadata file must exist in each log dir)

The upstream intention is for users to execute the [storage tool](https://kafka.apache.org/documentation/#kraft_storage) to achieve this, but this module contains a few extra options to automate this:

- [`services.apache-kafka.clusterId`](options.html#opt-services.apache-kafka.clusterId)

- [`services.apache-kafka.formatLogDirs`](options.html#opt-services.apache-kafka.formatLogDirs)

- [`services.apache-kafka.formatLogDirsIgnoreFormatted`](options.html#opt-services.apache-kafka.formatLogDirsIgnoreFormatted)
