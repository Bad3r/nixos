## Clustering

FoundationDB on NixOS works similarly to other Linux systems, so this section will be brief. Please refer to the full FoundationDB documentation for more on clustering.

FoundationDB organizes clusters using a set of _coordinators_, which are just specially-designated worker processes. By default, every installation of FoundationDB on NixOS will start as its own individual cluster, with a single coordinator: the first worker process on **localhost**.

Coordinators are specified globally using the **/etc/foundationdb/fdb.cluster** file, which all servers and client applications will use to find and join coordinators. Note that this file _can not_ be managed by NixOS so easily: FoundationDB is designed so that it will rewrite the file at runtime for all clients and nodes when cluster coordinators change, with clients transparently handling this without intervention. It is fundamentally a mutable file, and you should not try to manage it in any way in NixOS.

When dealing with a cluster, there are two main things you want to do:

- Add a node to the cluster for storage/compute.

- Promote an ordinary worker to a coordinator.

A node must already be a member of the cluster in order to properly be promoted to a coordinator, so you must always add it first if you wish to promote it.

To add a machine to a FoundationDB cluster:

- Choose one of the servers to start as the initial coordinator.

- Copy the **/etc/foundationdb/fdb.cluster** file from this server to all the other servers. Restart FoundationDB on all of these other servers, so they join the cluster.

- All of these servers are now connected and working together in the cluster, under the chosen coordinator.

At this point, you can add as many nodes as you want by just repeating the above steps. By default there will still be a single coordinator: you can use **fdbcli** to change this and add new coordinators.

As a convenience, FoundationDB can automatically assign coordinators based on the redundancy mode you wish to achieve for the cluster. Once all the nodes have been joined, simply set the replication policy, and then issue the **coordinators auto** command

For example, assuming we have 3 nodes available, we can enable double redundancy mode, then auto-select coordinators. For double redundancy, 3 coordinators is ideal: therefore FoundationDB will make _every_ node a coordinator automatically:

```programlisting
fdbcli> configure double ssd
fdbcli> coordinators auto
```

This will transparently update all the servers within seconds, and appropriately rewrite the **fdb.cluster** file, as well as informing all client processes to do the same.
