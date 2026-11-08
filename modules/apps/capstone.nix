/*
  Package: capstone
  Description: Multi-architecture disassembly engine and command-line tool.
  Homepage: https://www.capstone-engine.org/
  Documentation: https://www.capstone-engine.org/cstool.html
  Repository: https://github.com/capstone-engine/capstone

  Summary:
    * Supplies the Capstone disassembly library and the `cstool` command.
    * Supports disassembly for multiple processor architectures.
*/
_:
let
  CapstoneModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.capstone.extended;
    in
    {
      options.programs.capstone.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the Capstone disassembler.";
        };

        package = lib.mkPackageOption pkgs "capstone" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.capstone = CapstoneModule;
}
