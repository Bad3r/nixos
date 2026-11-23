/*
  Package: bloaty
  Description: Size profiler for binaries.
  Homepage: https://github.com/google/bloaty
  Documentation: https://github.com/google/bloaty/blob/main/doc/using.md
  Repository: https://github.com/google/bloaty

  Summary:
    * Breaks down ELF, Mach-O, PE, and WebAssembly binary size by section, symbol, or compile unit.
    * Diffs the size of two builds.
*/
_:
let
  BloatyModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.bloaty.extended;
    in
    {
      options.programs.bloaty.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Bloaty.";
        };

        package = lib.mkPackageOption pkgs "bloaty" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.bloaty = BloatyModule;
}
