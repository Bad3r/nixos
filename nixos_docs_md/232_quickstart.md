## Quickstart

This module is designed to use Unix domain sockets as the socket paths can be automatically configured for multiple instances, but TCP sockets are also supported.

A minimal configuration with [nginx](options.html#opt-services.nginx.enable) may look like the following:

```programlisting
{ config, ... }:
{
  services.anubis.instances.default.settings.TARGET = "http://localhost:8000";

  # required due to unix socket permissions

  users.users.nginx.extraGroups = [ config.users.groups.anubis.name ];
  services.nginx.virtualHosts."example.com" = {
    locations = {
      "/".proxyPass = "http://unix:${config.services.anubis.instances.default.settings.BIND}";
    };
  };
}
```

If Unix domain sockets are not needed or desired, this module supports operating with only TCP sockets.

```programlisting
{
  services.anubis = {
    instances.default = {
      settings = {
        TARGET = "http://localhost:8080";
        BIND = ":9000";
        BIND_NETWORK = "tcp";
        METRICS_BIND = "127.0.0.1:9001";
        METRICS_BIND_NETWORK = "tcp";
      };
    };
  };
}
```
