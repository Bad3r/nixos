/*
  Package: cloudflare-warp
  Variant: headless (warp-cli + warp-svc; no GUI taskbar, no XDG autostart)
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
_:
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
          description = "Whether to enable cloudflare-warp.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.cloudflare-warp.override { headless = true; };
          defaultText = lib.literalExpression "pkgs.cloudflare-warp.override { headless = true; }";
          description = ''
            Cloudflare WARP package. Defaults to the headless build, which
            ships only `warp-cli` and `warp-svc` and omits the GUI taskbar,
            `etc/xdg/autostart/com.cloudflare.WarpTaskbar.desktop`, and the
            `share/systemd/user/warp-taskbar.service` user unit. Set to
            `pkgs.cloudflare-warp` to install the GUI variant.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [
    "cloudflare-warp"
    "cloudflare-warp-headless"
  ];

  flake.nixosModules.apps.cloudflare-warp = CloudflareWarpModule;
}
