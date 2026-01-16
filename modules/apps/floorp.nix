/*
  Package: floorp
  Description: Fork of Firefox that seeks balance between versatility, privacy and web openness.
  Homepage: https://floorp.app/
  Documentation: https://docs.floorp.app/
  Repository: https://github.com/Floorp-Projects/Floorp

  Summary:
    * Provides a privacy-focused Firefox fork with workspaces, vertical tabs, and customizable interface features.
    * Supports enterprise policies, profile management, and headless automation inherited from Firefox.

  Options:
    --private-window <url>: Open a URL directly in a new private browsing window.
    --ProfileManager: Launch the profile manager to create or select profiles.
    --new-window <url>: Open a new window with the provided URL.
    --headless: Run Floorp without a visible UI for automated testing or printing.
    --safe-mode: Start Floorp with extensions disabled for troubleshooting.
*/
_:
let
  FloorpModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.floorp.extended;
    in
    {
      options.programs.floorp.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable floorp.";
        };

        package = lib.mkPackageOption pkgs "floorp-bin" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.floorp = FloorpModule;
}
