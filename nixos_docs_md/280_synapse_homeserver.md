## Synapse Homeserver

[Synapse](https://github.com/element-hq/synapse) is the reference homeserver implementation of Matrix from the core development team at matrix.org.

Before deploying synapse server, a postgresql database must be set up. For that, please make sure that postgresql is running and the following SQL statements to create a user & database called `matrix-synapse` were executed before synapse starts up:

```programlisting
CREATE ROLE "matrix-synapse";
CREATE DATABASE "matrix-synapse" WITH OWNER "matrix-synapse"
  TEMPLATE template0
  LC_COLLATE = "C"
  LC_CTYPE = "C";
```

Usually, it’s sufficient to do this once manually before continuing with the installation.

Please make sure to set a different password.

The following configuration example will set up a synapse server for the `example.org` domain, served from the host `myhostname.example.org`. For more information, please refer to the [installation instructions of Synapse](https://element-hq.github.io/synapse/latest/setup/installation.html) .

```programlisting
{
  pkgs,
  lib,
  config,
  ...
}:
let
  fqdn = "${config.networking.hostName}.${config.networking.domain}";
  baseUrl = "https://${fqdn}";
  clientConfig."m.homeserver".base_url = baseUrl;
  serverConfig."m.server" = "${fqdn}:443";
  mkWellKnown = data: ''
    default_type application/json;
    add_header Access-Control-Allow-Origin *;
    return 200 '${builtins.toJSON data}';
  '';
in
{
  networking.hostName = "myhostname";
  networking.domain = "example.org";
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  services.postgresql.enable = true;

  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    virtualHosts = {
      # If the A and AAAA DNS records on example.org do not point on the same host as the

      # records for myhostname.example.org, you can easily move the /.well-known

      # virtualHost section of the code to the host that is serving example.org, while

      # the rest stays on myhostname.example.org with no other changes required.

      # This pattern also allows to seamlessly move the homeserver from

      # myhostname.example.org to myotherhost.example.org by only changing the

      # /.well-known redirection target.

      "${config.networking.domain}" = {
        enableACME = true;
        forceSSL = true;
        # This section is not needed if the server_name of matrix-synapse is equal to

        # the domain (i.e. example.org from @foo:example.org) and the federation port

        # is 8448.

        # Further reference can be found in the docs about delegation under

        # https://element-hq.github.io/synapse/latest/delegate.html

        locations."= /.well-known/matrix/server".extraConfig = mkWellKnown serverConfig;
        # This is usually needed for homeserver discovery (from e.g. other Matrix clients).

        # Further reference can be found in the upstream docs at

        # https://spec.matrix.org/latest/client-server-api/#getwell-knownmatrixclient

        locations."= /.well-known/matrix/client".extraConfig = mkWellKnown clientConfig;
      };
      "${fqdn}" = {
        enableACME = true;
        forceSSL = true;
        # It's also possible to do a redirect here or something else, this vhost is not

        # needed for Matrix. It's recommended though to *not put* element

        # here, see also the section about Element.

        locations."/".extraConfig = ''
          return 404;
        '';
        # Forward all Matrix API calls to the synapse Matrix homeserver. A trailing slash

        # *must not* be used here.

        locations."/_matrix".proxyPass = "http://[::1]:8008";
        # Forward requests for e.g. SSO and password-resets.

        locations."/_synapse/client".proxyPass = "http://[::1]:8008";
      };
    };
  };

  services.matrix-synapse = {
    enable = true;
    settings.server_name = config.networking.domain;
    # The public base URL value must match the `base_url` value set in `clientConfig` above.

    # The default value here is based on `server_name`, so if your `server_name` is different

    # from the value of `fqdn` above, you will likely run into some mismatched domain names

    # in client applications.

    settings.public_baseurl = baseUrl;
    settings.listeners = [
      {
        port = 8008;
        bind_addresses = [ "::1" ];
        type = "http";
        tls = false;
        x_forwarded = true;
        resources = [
          {
            names = [
              "client"
              "federation"
            ];
            compress = true;
          }
        ];
      }
    ];
  };
}
```
