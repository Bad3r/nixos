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

  iOS/Mach-O Capabilities:
    * Native Mach-O format support with fat binary handling.
    * DYLD cache extraction and analysis.
    * Objective-C class and method analysis.
    * ARM64 disassembly optimized for iOS/macOS binaries.
    * Integration with class-dump for symbol extraction.

  Workflow for IPA Files:
    1. Extract IPA: `unzip app.ipa && cd Payload/*.app/`
    2. Analyze binary: `r2 -A ./AppBinary`
    3. List functions: `afl`
    4. Disassemble function: `pdf @ sym.function_name`
    5. Export analysis: `agj > callgraph.json`

  Options:
    r2 -A <binary>: Auto-analyze binary on load.
    r2 -d <binary>: Debug mode (requires iOS device with frida-server or local debugging).
    r2 -w <binary>: Open in write mode for patching.
    rabin2 -I <binary>: Display binary information (architecture, imports, etc.).
    rasm2 -d '<hex>': Disassemble hex opcodes.

  Example Usage:
    * `r2 -A MyApp` — Analyze iOS app binary and list functions.
    * `rabin2 -I MyApp` — Display Mach-O header info, architecture, entry points.
    * `r2 -c 'aa; afl; pdf @ main' MyApp` — Auto-analyze and decompile main function.
    * `r2 -c 'iS' MyApp` — List all sections in the binary.

  Integration:
    * Use with iaito (GUI frontend) for visual analysis.
    * Combine with r2ghidra-dec plugin for Ghidra decompiler integration.
    * Export to Frida for dynamic analysis on jailbroken devices.
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
          description = lib.mdDoc "Whether to enable radare2 reverse engineering framework.";
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
