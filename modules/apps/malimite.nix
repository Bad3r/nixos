/*
  Package: malimite
  Description: iOS and macOS decompiler built on Ghidra.
  Documentation: https://github.com/LaurieWired/Malimite/wiki
  Repository: https://github.com/LaurieWired/Malimite

  Summary:
    * Decompiles IPA files and application bundles with direct support for Swift, Objective-C, and Apple resources.
    * Reconstructs Swift classes and translates methods with a built-in LLM.
*/
_:
let
  MalimiteModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.malimite.extended;
    in
    {
      options.programs.malimite.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Malimite iOS and macOS decompiler.";
        };

        package = lib.mkPackageOption pkgs "malimite" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.malimite = MalimiteModule;
}
