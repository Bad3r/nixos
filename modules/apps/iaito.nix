/*
  Package: iaito
  Description: Official Qt-based GUI for radare2 reverse engineering framework.
  Homepage: https://rada.re/n/iaito.html
  Documentation: https://github.com/radareorg/iaito
  Repository: https://github.com/radareorg/iaito

  Summary:
    * Provides visual disassembly, hex editor, graph view, and function browser.

  Options:
    iaito -A <level> <binary>: Open a binary and run analysis at level 0-3.
*/
_:
let
  IaitoModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.iaito.extended;
    in
    {
      options.programs.iaito.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable iaito (radare2 GUI frontend).";
        };

        package = lib.mkPackageOption pkgs "iaito" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.iaito = IaitoModule;
}
