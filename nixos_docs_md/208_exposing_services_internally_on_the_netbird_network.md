## Exposing services internally on the Netbird network

You can easily expose services exclusively to Netbird network by combining [`networking.firewall.interfaces`](options.html#opt-networking.firewall.interfaces) rules with [`interface`](options.html#opt-services.netbird.clients._name_.interface) names:

```programlisting
{
  services.netbird.clients.priv.port = 51819;
  services.netbird.clients.work.port = 51818;
  networking.firewall.interfaces = {
    "${config.services.netbird.clients.priv.interface}" = {
      allowedUDPPorts = [ 1234 ];
    };
    "${config.services.netbird.clients.work.interface}" = {
      allowedTCPPorts = [ 8080 ];
    };
  };
}
```

### Additional customizations

Each Netbird client service by default:

- runs in a [hardened](options.html#opt-services.netbird.clients._name_.hardened) mode,

- starts with the system,

- [opens up a firewall](options.html#opt-services.netbird.clients._name_.openFirewall) for direct (without TURN servers) peer-to-peer communication,

- can be additionally configured with environment variables,

- automatically determines whether `netbird-ui-<name>` should be available,

- does not enable [routing features](options.html#opt-services.netbird.useRoutingFeatures) by default If you plan to use routing features, you must explicitly enable them. By enabling them, the service will configure the firewall and enable IP forwarding on the system. When set to `client` or `both`, reverse path filtering will be set to loose instead of strict. When set to `server` or `both`, IP forwarding will be enabled.

[autoStart](options.html#opt-services.netbird.clients._name_.autoStart) allows you to start the client (an actual systemd service) on demand, for example to connect to work-related or otherwise conflicting network only when required. See the option description for more information.

[environment](options.html#opt-services.netbird.clients._name_.environment) allows you to pass additional configurations through environment variables, but special care needs to be taken for overriding config location and daemon address due [hardened](options.html#opt-services.netbird.clients._name_.hardened) option.
