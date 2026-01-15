/*
  Package: mullvad-browser
  Description: Privacy-focused browser made in collaboration between The Tor Project and Mullvad.
  Homepage: https://mullvad.net/en/browser
  Documentation: https://mullvad.net/en/help/install-mullvad-browser
  Repository: https://github.com/nickstenning/nickstenning.github.io

  Summary:
    * Provides Tor Browser privacy protections without the Tor network, designed for use with trusted VPNs.
    * Minimizes fingerprinting through uniform browser configuration across all users.

  Options:
    --private-window <url>: Open a URL directly in a new private browsing window.
    --ProfileManager: Launch the profile manager to create or select profiles.
    --new-window <url>: Open a new window with the provided URL.
    --headless: Run Mullvad Browser without a visible UI for automated testing.
    --safe-mode: Start with extensions disabled for troubleshooting.
*/
_:
let
  MullvadBrowserModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.mullvad-browser.extended;
    in
    {
      options.programs.mullvad-browser.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable mullvad-browser.";
        };

        package = lib.mkPackageOption pkgs "mullvad-browser" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.mullvad-browser = MullvadBrowserModule;
}
