# Local web UIs at http://<name>: each site is an /etc/hosts name on loopback
# and an nginx virtual host on 127.0.0.1:80 that proxies to its upstream.
_:
let
  body =
    { config, lib, ... }:
    let
      sites = config.networking.loopbackSites;
      listen = [
        {
          addr = "127.0.0.1";
          port = 80;
        }
      ];
    in
    {
      options.networking.loopbackSites = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              upstream = lib.mkOption {
                type = lib.types.str;
                example = "http://127.0.0.1:5600";
                description = "URL that nginx proxies the name to.";
              };

              hostHeader = lib.mkOption {
                type = lib.types.str;
                default = "$host";
                example = "127.0.0.1";
                description = ''
                  Host header sent upstream, as an nginx value. The default passes
                  the requested name on; a fixed value suits upstreams that accept
                  only their own address.
                '';
              };
            };
          }
        );
        default = { };
        description = "Local web UIs served on loopback port 80, keyed by hostname.";
      };

      config = lib.mkIf (sites != { }) {
        networking.hosts."127.0.0.1" = lib.attrNames sites;

        services.nginx = {
          enable = true;
          virtualHosts = {
            # Closes requests for any other name, so a DNS-rebinding page
            # cannot reach an upstream through a rewritten Host header.
            loopback-sites-reject = {
              default = true;
              serverName = "_";
              inherit listen;
              locations."/".return = "444";
            };
          }
          // lib.mapAttrs (_: site: {
            inherit listen;
            locations."/" = {
              proxyPass = site.upstream;
              recommendedProxySettings = false;
              extraConfig = "proxy_set_header Host ${site.hostHeader};";
            };
          }) sites;
        };
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
