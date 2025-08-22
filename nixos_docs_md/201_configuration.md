## Configuration

pihole-FTL can be configured with [`services.pihole-ftl.settings`](options.html#opt-services.pihole-ftl.settings), which controls the content of `pihole.toml`.

The template pihole.toml is provided in `pihole-ftl.passthru.settingsTemplate`, which describes all settings.

Example configuration:

```programlisting
{
  services.pihole-ftl = {
    enable = true;
    openFirewallDNS = true;
    openFirewallDHCP = true;
    queryLogDeleter.enable = true;
    lists = [
      {
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        # Alternatively, use the file from nixpkgs. Note its contents won't be

        # automatically updated by Pi-hole, as it would with an online URL.

        # url = "file://${pkgs.stevenblack-blocklist}/hosts";

        description = "Steven Black's unified adlist";
      }
    ];
    settings = {
      dns = {
        domainNeeded = true;
        expandHosts = true;
        interface = "br-lan";
        listeningMode = "BIND";
        upstreams = [ "127.0.0.1#5053" ];
      };
      dhcp = {
        active = true;
        router = "192.168.10.1";
        start = "192.168.10.2";
        end = "192.168.10.254";
        leaseTime = "1d";
        ipv6 = true;
        multiDNS = true;
        hosts = [
          # Static address for the current host

          "aa:bb:cc:dd:ee:ff,192.168.10.1,${config.networking.hostName},infinite"
        ];
        rapidCommit = true;
      };
      misc.dnsmasq_lines = [
        # This DHCP server is the only one on the network

        "dhcp-authoritative"
        # Source: https://data.iana.org/root-anchors/root-anchors.xml

        "trust-anchor=.,38696,8,2,683D2D0ACB8C9B712A1948B27F741219298D0A450D612C483AF444A4C0FB2B16"
      ];
    };
  };
}
```

### Inheriting configuration from Dnsmasq

If [`services.pihole-ftl.useDnsmasqConfig`](options.html#opt-services.pihole-ftl.useDnsmasqConfig) is enabled, the configuration [options of the Dnsmasq module](#module-services-networking-dnsmasq) will be automatically used by pihole-FTL. Note that this may cause duplicate option errors depending on pihole-FTL settings.

See the [Dnsmasq example](#module-services-networking-dnsmasq-configuration-home) for an exemplar Dnsmasq configuration. Make sure to set [`services.dnsmasq.enable`](options.html#opt-services.dnsmasq.enable) to false and [`services.pihole-ftl.enable`](options.html#opt-services.pihole-ftl.enable) to true instead:

```programlisting
{
  services.pihole-ftl = {
    enable = true;
    useDnsmasqConfig = true;
  };
}
```

### Serving on multiple interfaces

Pi-hole’s configuration only supports specifying a single interface. If you want to configure additional interfaces with different configuration, use `misc.dnsmasq_lines` to append extra Dnsmasq options.

```programlisting
{
  services.pihole-ftl = {
    settings.misc.dnsmasq_lines = [
      # Specify the secondary interface

      "interface=enp1s0"
      # A different device is the router on this network, e.g. the one

      # provided by your ISP

      "dhcp-option=enp1s0,option:router,192.168.0.1"
      # Specify the IPv4 ranges to allocate, with a 1-day lease time

      "dhcp-range=enp1s0,192.168.0.10,192.168.0.253,1d"
      # Enable IPv6

      "dhcp-range=::f,::ff,constructor:enp1s0,ra-names,ra-stateless"
    ];
  };
}
```
