/*
  Package: cloudflare-warp
  Description: Cloudflare WARP client delivering encrypted consumer VPN and Zero Trust connectivity.
  Homepage: https://developers.cloudflare.com/warp-client/
  Documentation: https://developers.cloudflare.com/warp-client/get-started/linux/
  Repository: https://github.com/cloudflare/warp

  Summary:
    * Secures device traffic using WireGuard-based tunnels through Cloudflare's global edge network.
    * Integrates with Cloudflare Zero Trust policies for split tunneling, device posture, and secure web gateway enforcement.

  Options:
    --accept-tos: Accept Cloudflare's Terms of Service non-interactively when registering with `warp-cli register --accept-tos`.
    --warp: Select the full WARP mode using `warp-cli mode --warp` instead of the default Gateway-only mode.
    --add --ip <cidr>: Extend split tunneling by combining `warp-cli split-tunnel --add --ip <cidr>`.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  CloudflareWarpModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."cloudflare-warp".extended;
    in
    {
      options.programs.cloudflare-warp.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable cloudflare-warp.";
        };

        package = lib.mkPackageOption pkgs "cloudflare-warp" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.cloudflare-warp = CloudflareWarpModule;
}
