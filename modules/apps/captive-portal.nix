/*
  Package: captive-portal
  Description: Sign in to a captive portal on a host whose DNS is claimed by Tailscale.
  Homepage: https://github.com/Bad3r/nixos
  Documentation: docs/networking/README.md
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Releases DNS from Tailscale back to NetworkManager's dnsmasq so the access point's resolver answers again.
    * Locates the sign-in page through the access point's own resolver and HTTP probes, then opens it.
    * Restores the saved Tailscale DNS and run state once the portal accepts the session.

  Options:
    captive-portal: Release DNS, find the portal, and open it in the default browser.
    captive-portal --probe: Report portal state and URL without changing DNS.
    captive-portal --restore: Hand DNS back to Tailscale after signing in.
    --device DEV: Inspect a specific device instead of the first connected wifi/ethernet.
    --no-open: Print the portal URL instead of launching a browser.
    --down: Stop Tailscale entirely rather than only releasing DNS.

  Example Usage:
    * `captive-portal --probe` -- Check whether the current network intercepts DNS or HTTP.
    * `captive-portal` -- Sign in to a hotel or campus network.
    * `captive-portal --restore` -- Return to tailnet DNS after the portal accepts the session.
*/
_:
let
  CaptivePortalModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.captive-portal.extended;
    in
    {
      options.programs.captive-portal.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable captive-portal.";
        };

        package = lib.mkPackageOption pkgs "captive-portal" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.captive-portal = CaptivePortalModule;
}
