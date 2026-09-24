/*
  Package: imhex
  Description: Hex editor for analyzing and editing binary data.
  Homepage: https://imhex.org/
  Documentation: https://imhex.org/
  Repository: https://github.com/WerWolv/ImHex

  Summary:
    * Displays binary data with a hex view, data inspector, and visualizations.
    * Applies pattern definitions to parse and highlight structured data.
*/
_:
let
  ImHexModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.imhex.extended;
    in
    {
      options.programs.imhex.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ImHex.";
        };

        package = lib.mkPackageOption pkgs "imhex" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.imhex = ImHexModule;
}
