## Administration

_pihole command documentation_: [https://docs.pi-hole.net/main/pihole-command](https://docs.pi-hole.net/main/pihole-command)

Enabling pihole-FTL provides the `pihole` command, which can be used to control the daemon and some configuration.

Note that in NixOS the script has been patched to remove the reinstallation, update, and Dnsmasq configuration commands. In NixOS, Pi-hole’s configuration is immutable and must be done with NixOS options.

For more convenient administration and monitoring, see [Pi-hole Dashboard](#module-services-web-apps-pihole-web "Pi-hole Web Dashboard")
