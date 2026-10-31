/*
  Package: ghidra
  Description: NSA's software reverse engineering (SRE) framework with powerful disassembler and decompiler.
  Homepage: https://ghidra-sre.org/
  Documentation: https://ghidra.re/
  Repository: https://github.com/NationalSecurityAgency/ghidra

  Summary:
    * Industry-grade reverse engineering tool with multi-architecture support (x86, ARM, MIPS, PowerPC, etc.).
    * Excellent Mach-O binary support for iOS/macOS reverse engineering, including DYLD cache analysis.
    * Features include decompiler, scripting (Python/Java), collaborative analysis, and extensible plugin system.
*/
_:
let
  GhidraModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ghidra.extended;
    in
    {
      options.programs.ghidra.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Ghidra reverse engineering framework.";
        };

        package = lib.mkPackageOption pkgs "ghidra" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ghidra = GhidraModule;
}
