/*
  Package: firefox
  Description: Mozilla Firefox web browser with security, privacy, and developer tooling features.
  Homepage: https://www.mozilla.org/firefox/
  Documentation: https://support.mozilla.org/
  Repository: https://hg.mozilla.org/mozilla-central/

  Summary:
    * Delivers a multi-process web browser with tracking protection, container tabs, integrated devtools, and broad web standards support.
    * Supports headless automation, dedicated profiles, and enterprise policies for tailored deployments.

  Options:
    --private-window <url>: Open a URL directly in a new private browsing window.
    --ProfileManager: Launch the profile manager to create or select profiles.
    --new-window <url>: Open a new window with the provided URL.
    --headless: Run Firefox without a visible UI for automated testing or printing.
    --safe-mode: Start Firefox with extensions disabled for troubleshooting.

  Example Usage:
    * `firefox https://example.com` — Launch Firefox and navigate to a website.
    * `firefox --profile ~/.mozilla/firefox/work --private-window https://intranet.local` — Use a dedicated profile and private window for sensitive browsing.
    * `firefox --headless --screenshot page.png https://example.com` — Capture a screenshot via the headless renderer.
*/
_:
let
  FirefoxModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.firefox.extended;
    in
    {
      options.programs.firefox.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable firefox.";
        };

        package = lib.mkPackageOption pkgs "firefox" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.firefox = FirefoxModule;
}
