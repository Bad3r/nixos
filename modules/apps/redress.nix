/*
  Package: redress
  Description: Go binary analysis tool.
  Homepage: https://github.com/goretk/redress
  Documentation: https://github.com/goretk/redress#readme
  Repository: https://github.com/goretk/redress

  Summary:
    * Extracts packages, types, interfaces, methods, and the source tree layout from stripped Go binaries.
    * Runs as a radare2 plugin through r2pipe.
*/
_:
let
  RedressModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.redress.extended;
    in
    {
      options.programs.redress.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable redress.";
        };

        package = lib.mkPackageOption pkgs "redress" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.redress = RedressModule;
}
