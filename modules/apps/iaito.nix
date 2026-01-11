/*
  Package: iaito
  Description: Official Qt-based GUI for radare2 reverse engineering framework.
  Homepage: https://rada.re/n/iaito.html
  Documentation: https://github.com/radareorg/iaito
  Repository: https://github.com/radareorg/iaito

  Summary:
    * Native GUI frontend for radare2 with modern Qt interface.
    * Provides visual disassembly, hex editor, graph view, and function browser.
    * Lighter weight alternative to Cutter, tightly integrated with radare2.

  iOS/Mach-O Features:
    * Visual Mach-O binary inspection with architecture selection.
    * ARM64 instruction highlighting and navigation.
    * Function call graphs and control flow visualization.
    * Objective-C class browser for runtime analysis.

  Workflow for IPA Files:
    1. Extract IPA: `unzip app.ipa && cd Payload/*.app/`
    2. Launch iaito: `iaito ./AppBinary`
    3. Choose analysis level (Auto-analysis recommended for iOS apps)
    4. Browse functions, strings, imports in sidebar
    5. View disassembly, graph, and hex in synchronized panels

  Key Features:
    * Multi-panel layout: Functions list, disassembly, graph, hex editor.
    * Interactive CFG: Click nodes to navigate between basic blocks.
    * String references: Find hardcoded credentials, API keys, URLs.
    * Symbol table: Browse all Objective-C classes and methods.
    * radare2 console: Direct r2 command access for advanced operations.

  Options:
    iaito: Launch GUI application.
    iaito <binary>: Open specific binary file.
    iaito -A <binary>: Open with auto-analysis enabled.

  Example Usage:
    * `iaito MyApp` — Open iOS binary in GUI.
    * Use Graph view to visualize function control flow.
    * Search panel (Ctrl+F) to find strings, symbols, or byte patterns.
    * Console tab provides full radare2 command-line access.

  Integration:
    * Direct radare2 backend - all r2 commands work seamlessly.
    * Can export analysis to Ghidra format via r2 plugins.
    * Lighter resource usage compared to Cutter (better for large binaries).
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
