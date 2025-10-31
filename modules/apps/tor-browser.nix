/*
  Package: tor-browser
  Description: Privacy-focused Firefox-based browser routed through the Tor network for anonymous browsing.
  Homepage: https://www.torproject.org/
  Documentation: https://tb-manual.torproject.org/
  Repository: https://gitlab.torproject.org/tpo/applications/tor-browser

  Summary:
    * Bundles Tor daemon and hardened Firefox configuration to enforce circuit isolation, anti-fingerprinting, and security patches.
    * Includes Tor Launcher, NoScript, HTTPS-Only mode, and update channels managed by the Tor Project.

  Options:
    tor-browser: Launch the browser with Tor connection bootstrap wizard.
    TOR_SKIP_LAUNCH=1 tor-browser: Connect to existing system tor daemon instead of launching internal one.
    TOR_CONTROL_PORT: Configure Tor control port for advanced setups (e.g., bridges, custom proxies).

  Example Usage:
    * `tor-browser` — Start Tor Browser and connect to the Tor network using the default launcher.
    * Configure bridges via “Tor Network Settings” if bypassing censorship is required.
    * Set Security Level to “Safest” via the shield icon for maximal script blocking.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.tor-browser.extended;
  TorBrowserModule = {
    options.programs.tor-browser.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable tor-browser.";
      };

      package = lib.mkPackageOption pkgs "tor-browser" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.tor-browser = TorBrowserModule;
}
