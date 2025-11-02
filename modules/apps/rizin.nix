/*
  Package: rizin
  Description: Fork of radare2 with improved stability, modernized codebase, and cleaner architecture.
  Homepage: https://rizin.re/
  Documentation: https://book.rizin.re/
  Repository: https://github.com/rizinorg/rizin

  Summary:
    * Community-driven radare2 fork focused on usability and code quality.
    * Backward compatible with r2 but with improved APIs and better documentation.
    * Enhanced analysis engine with better type inference and decompilation.

  iOS/Mach-O Capabilities:
    * Full Mach-O binary format support inherited from radare2.
    * Improved ARM64 analysis with better instruction lifting.
    * DYLD cache support for analyzing iOS system frameworks.
    * Objective-C and Swift runtime introspection.

  Workflow for IPA Files:
    1. Extract and navigate: `unzip app.ipa && cd Payload/*.app/`
    2. Open with analysis: `rz-bin -I ./AppBinary` (display binary info)
    3. Interactive analysis: `rizin -A ./AppBinary`
    4. Explore functions: `afl` (list functions)
    5. Decompile: `pdg @ sym.function_name` (print decompiled graph)

  Options:
    rizin -A <binary>: Auto-analyze binary on load.
    rizin -w <binary>: Open in write mode for binary patching.
    rz-bin -I <binary>: Display binary information.
    rz-asm -d '<hex>': Disassemble hex opcodes.
    rz-ax <expr>: Evaluate mathematical/hex expressions.

  Example Usage:
    * `rizin -A MyApp` — Analyze iOS binary with auto-analysis.
    * `rz-bin -I MyApp` — Show Mach-O metadata (architecture, imports, entry point).
    * `rizin -c 'aaa; afl' MyApp` — Deep analysis and list all functions.
    * Use with Cutter GUI for visual reverse engineering experience.

  Integration:
    * Works seamlessly with Cutter (official GUI frontend).
    * Compatible with r2 scripts and plugins (with minor adjustments).
    * Better suited for scripting due to cleaner API design.
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
          description = lib.mdDoc "Whether to enable Rizin reverse engineering framework.";
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
