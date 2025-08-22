## IPv6 Configuration

IPv6 is enabled by default. Stateless address autoconfiguration is used to automatically assign IPv6 addresses to all interfaces, and Privacy Extensions (RFC 4941) are enabled by default. You can adjust the default for this by setting [`networking.tempAddresses`](options.html#opt-networking.tempAddresses). This option may be overridden on a per-interface basis by [`networking.interfaces.<name>.tempAddress`](options.html#opt-networking.interfaces._name_.tempAddress). You can disable IPv6 support globally by setting:

```programlisting
{ networking.enableIPv6 = false; }
```

You can disable IPv6 on a single interface using a normal sysctl (in this example, we use interface `eth0`):

```programlisting
{ boot.kernel.sysctl."net.ipv6.conf.eth0.disable_ipv6" = true; }
```

As with IPv4 networking interfaces are automatically configured via DHCPv6. You can configure an interface manually:

```programlisting
{
  networking.interfaces.eth0.ipv6.addresses = [
    {
      address = "fe00:aa:bb:cc::2";
      prefixLength = 64;
    }
  ];
}
```

For configuring a gateway, optionally with explicitly specified interface:

```programlisting
{
  networking.defaultGateway6 = {
    address = "fe00::1";
    interface = "enp0s3";
  };
}
```

See [the section called “IPv4 Configuration”](#sec-ipv4 "IPv4 Configuration") for similar examples and additional information.
