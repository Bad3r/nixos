/*
  Package: rizin
  Description: Fork of radare2 with improved stability, modernized codebase, and cleaner architecture.
  Homepage: https://rizin.re/
  Documentation: https://book.rizin.re/
  Repository: https://github.com/rizinorg/rizin

  Summary:
    * Backward compatible with r2 but with improved APIs and better documentation.
    * Enhanced analysis engine with better type inference and decompilation.

  Options:
    rizin -A <binary>: Auto-analyze binary on load.
    rizin -w <binary>: Open in write mode for binary patching.
    rz-bin -I <binary>: Display binary information.
    rz-asm -d '<hex>': Disassemble hex opcodes.
*/
_:
let
  RizinModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.rizin.extended;
    in
    {
      options.programs.rizin.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Rizin reverse engineering framework.";
        };

        package = lib.mkPackageOption pkgs "rizin" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.rizin = RizinModule;
}
