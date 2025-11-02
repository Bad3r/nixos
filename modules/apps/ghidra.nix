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

  iOS/IPA Analysis Capabilities:
    * Native Mach-O loader with Universal Binary support - can extract and analyze specific architectures.
    * DYLD shared cache extraction via DyldCacheExtractLoader - critical for analyzing iOS system frameworks.
    * Built-in analyzers: MachoFunctionStartsAnalyzer, DyldCacheAnalyzer, iOS_KextStubFixupAnalyzer.
    * Swift/Objective-C runtime analysis with symbol demangling support.
    * Load command processing (LC_FUNCTION_STARTS, LC_REEXPORT_DYLIB) for improved analysis.

  Workflow for IPA Files:
    1. Extract IPA: `unzip app.ipa` (IPA files are ZIP archives)
    2. Navigate to binary: `cd Payload/App.app/`
    3. Import into Ghidra: File → Import File → select Mach-O binary
    4. Select architecture from Universal Binary if needed
    5. Run auto-analysis with Mach-O specific analyzers enabled

  Options:
    ghidra: Launch the GUI for interactive analysis.
    ghidraRun <script.py>: Execute headless analysis scripts.
    GHIDRA_INSTALL_DIR: Set custom installation directory for extensions.

  Example Usage:
    * `ghidra` — Launch GUI and import IPA binary for analysis.
    * Configure loader options: enable libobjc.dylib linking for Objective-C runtime support.
    * Use DyldCacheExtractLoader for analyzing extracted dyld_shared_cache files.
    * Install Swift demangler extension for better symbol names in Swift binaries.

  Extensions:
    * Use `pkgs.ghidra.withExtensions` to add custom analyzers and plugins.
    * ghidra-extensions package set contains 12+ extensions in nixpkgs.
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
          description = lib.mdDoc "Whether to enable Ghidra reverse engineering framework.";
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
