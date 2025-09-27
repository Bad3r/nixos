/*
  Package: cloudflared
  Description: Cloudflare Tunnel daemon for exposing local services through Cloudflare's network.
  Homepage: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/
  Documentation: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/run-tunnel/
  Repository: https://github.com/cloudflare/cloudflared

  Summary:
    * Establishes outbound-only tunnels that publish private services without opening inbound firewall ports.
    * Integrates with Cloudflare Zero Trust policies, access rules, and load balancing for secure connectivity.

  Options:
    --config /etc/cloudflared/config.yml: Point the daemon at an alternate tunnel configuration file.
    --hostname <name>: Override the public hostname to route traffic through a specific tunnel.
    --no-autoupdate: Disable the built-in updater when running cloudflared in managed environments.
*/

{
  flake.nixosModules.apps.cloudflared =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cloudflared ];
    };
}
