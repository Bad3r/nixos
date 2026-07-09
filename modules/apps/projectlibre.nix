/*
  Package: projectlibre
  Description: Open-source desktop project management suite for Gantt scheduling, compatible with Microsoft Project files.
  Homepage: https://www.projectlibre.com/
  Documentation: https://projectlibre.com/projectlibre-documentation/
  Repository: https://sourceforge.net/p/projectlibre/code/

  Summary:
    * Provides Gantt chart scheduling, resource and cost management, and critical path analysis comparable to Microsoft Project.
    * Reads and writes native Microsoft Project `.mpp` files alongside its own format for cross-platform project file exchange.
*/
_:
let
  ProjectlibreModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.projectlibre.extended;
    in
    {
      options.programs.projectlibre.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable projectlibre.";
        };

        package = lib.mkPackageOption pkgs "projectlibre" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.projectlibre = ProjectlibreModule;
}
