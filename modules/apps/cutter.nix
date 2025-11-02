/*
  Package: cutter
  Description: Free and open-source reverse engineering platform powered by Rizin, with modern Qt GUI.
  Homepage: https://cutter.re/
  Documentation: https://cutter.re/docs/
  Repository: https://github.com/rizinorg/cutter

  Summary:
    * Official GUI frontend for Rizin reverse engineering framework.
    * Modern Qt-based interface with graph visualization, hex editor, and decompiler view.
    * Plugin system for extending functionality (Python, C++).

  iOS/Mach-O Features:
    * Visual Mach-O binary analysis with interactive function graphs.
    * ARM64 disassembly with syntax highlighting.
    * Decompiler window showing pseudo-C code alongside assembly.
    * Symbol navigation for Objective-C classes and Swift methods.

  Workflow for IPA Files:
    1. Extract IPA: `unzip app.ipa`
    2. Launch Cutter: `cutter`
    3. File → Open → Navigate to Payload/*.app/AppBinary
    4. Select analysis level (Auto-analysis recommended)
    5. Explore functions in left sidebar, view graphs/decompiler in main panels

  Key Features:
    * Graph view: Control flow and call graphs with interactive navigation.
    * Hex editor: View and modify binary data with syntax highlighting.
    * Decompiler: Ghidra-compatible decompilation (via r2ghidra plugin).
    * String/Symbol search: Quickly find interesting code points.
    * Scripting console: Python/R2 commands for automation.

  Options:
    cutter: Launch GUI application.
    cutter <binary>: Open binary directly in Cutter.
    cutter --help: Show all command-line options.

  Example Usage:
    * `cutter` — Launch GUI and open IPA binary interactively.
    * Use Graph view (Ctrl+G) to visualize function control flow.
    * Decompiler pane shows pseudo-C for selected functions.
    * Search strings (Shift+F12) to find hardcoded URLs, keys, etc.

  Integration:
    * Works with rizin backend - all rizin commands available via console.
    * Supports Ghidra decompiler via r2ghidra plugin.
    * Can load Ghidra projects for collaborative analysis.
*/
_:
let
  CutterModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.cutter.extended;
    in
    {
      options.programs.cutter.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable Cutter (Rizin GUI frontend).";
        };

        package = lib.mkPackageOption pkgs "cutter" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.cutter = CutterModule;
}
