## Quickstart

The absolute minimal configuration for the Netbird client daemon looks like this:

```programlisting
{ services.netbird.enable = true; }
```

This will set up a netbird service listening on the port `51820` associated to the `wt0` interface.

Which is equivalent to:

```programlisting
{
  services.netbird.clients.wt0 = {
    port = 51820;
    name = "netbird";
    interface = "wt0";
    hardened = false;
  };
}
```

This will set up a `netbird.service` listening on the port `51820` associated to the `wt0` interface. There will also be `netbird-wt0` binary installed in addition to `netbird`.

see [clients](options.html#opt-services.netbird.clients) option documentation for more details.
