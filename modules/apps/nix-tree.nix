/*
  Package: nix-tree
  Description: Interactive CLI for exploring Nix derivation dependency trees.
  Homepage: https://github.com/utdemir/nix-tree
  Documentation: https://github.com/utdemir/nix-tree#readme
  Repository: https://github.com/utdemir/nix-tree

  Summary:
    * Visualizes closure structure, outputs, and references for packages stored in the Nix store.
    * Provides TUI navigation, search, and export options to inspect build dependencies efficiently.

  Options:
    --derivation: Operate on the store derivation rather than its outputs.
*/
_:
let
  NixTreeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."nix-tree".extended;
    in
    {
      options.programs.nix-tree.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nix-tree.";
        };

        package = lib.mkPackageOption pkgs "nix-tree" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nix-tree = NixTreeModule;
}
