/*
  Package: lief
  Description: Library for parsing, inspecting, and modifying executable formats.
  Homepage: https://lief.quarkslab.com/
  Documentation: https://lief.quarkslab.com/doc/latest/
  Repository: https://github.com/lief-project/LIEF

  Summary:
    * Supports analysis and modification of ELF, PE, and Mach-O binaries.
    * Supplies the LIEF library for executable-format tooling.
*/
_:
let
  LiefModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.lief.extended;
    in
    {
      options.programs.lief.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the LIEF executable-format library.";
        };

        package = lib.mkPackageOption pkgs "lief" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.lief = LiefModule;
}
