## Advanced deployment options

### Confinement

The Akkoma systemd service may be confined to a chroot with

```programlisting
{ services.systemd.akkoma.confinement.enable = true; }
```

Confinement of services is not generally supported in NixOS and therefore disabled by default. Depending on the Akkoma configuration, the default confinement settings may be insufficient and lead to subtle errors at run time, requiring adjustment:

Use [`services.systemd.akkoma.confinement.packages`](options.html#opt-systemd.services._name_.confinement.packages) to make packages available in the chroot.

`services.systemd.akkoma.serviceConfig.BindPaths` and `services.systemd.akkoma.serviceConfig.BindReadOnlyPaths` permit access to outside paths through bind mounts. Refer to [`BindPaths=`](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#BindPaths=) of [systemd.exec(5)](https://www.freedesktop.org/software/systemd/man/systemd.exec.html) for details.

### Distributed deployment

Being an Elixir application, Akkoma can be deployed in a distributed fashion.

This requires setting [`services.akkoma.dist.address`](options.html#opt-services.akkoma.dist.address) and [`services.akkoma.dist.cookie`](options.html#opt-services.akkoma.dist.cookie). The specifics depend strongly on the deployment environment. For more information please check the relevant [Erlang documentation](https://www.erlang.org/doc/reference_manual/distributed.html).
