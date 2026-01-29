/*
  Package: quick-webapps
  Description: Web App Manager for the COSMIC desktop.
  Homepage: https://github.com/cosmic-utils/web-apps
  Documentation: https://github.com/cosmic-utils/web-apps
  Repository: https://github.com/cosmic-utils/web-apps

  Summary:
    * Creates web applications from URLs that run in separate windows using WebKitGTK.
    * Generates desktop launchers via the DynamicLauncher Portal with customizable names, icons, and categories.
*/
_:
let
  QuickWebappsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.quick-webapps.extended;
    in
    {
      options.programs.quick-webapps.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable quick-webapps.";
        };

        package = lib.mkPackageOption pkgs "quick-webapps" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.quick-webapps = QuickWebappsModule;
}
