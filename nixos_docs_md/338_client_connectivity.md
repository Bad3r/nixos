## Client connectivity

By default, all clients must use the current **fdb.cluster** file to access a given FoundationDB cluster. This file is located by default in **/etc/foundationdb/fdb.cluster** on all machines with the FoundationDB service enabled, so you may copy the active one from your cluster to a new node in order to connect, if it is not part of the cluster.
