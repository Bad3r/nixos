/*
  Package: radare2
  Description: Unix-like reverse engineering framework and command-line toolset for binary analysis.
  Homepage: https://rada.re/
  Documentation: https://book.rada.re/
  Repository: https://github.com/radareorg/radare2

  Summary:
    * Powerful disassembler, debugger, binary analysis, and hex editor framework.
    * Multi-architecture support including ARM64 (iOS), x86, MIPS, PowerPC, and more.
    * Scriptable via r2pipe (Python, JavaScript, etc.) and built-in commands.

  Options:
    r2 -A <binary>: Auto-analyze binary on load.
    r2 -d <binary>: Debug mode (requires iOS device with frida-server or local debugging).
    r2 -w <binary>: Open in write mode for patching.
    rabin2 -I <binary>: Display binary information (architecture, imports, etc.).
    rasm2 -d '<hex>': Disassemble hex opcodes.
*/
_:
let
  Radare2Module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.radare2.extended;
    in
    {
      options.programs.radare2.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable radare2 reverse engineering framework.";
        };

        package = lib.mkPackageOption pkgs "radare2" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.radare2 = Radare2Module;
}
