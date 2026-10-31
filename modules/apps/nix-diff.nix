/*
  Package: nix-diff
  Description: Compares the derivation graphs of two Nix outputs to show semantic differences.
  Homepage: https://github.com/Gabriel439/nix-diff
  Documentation: https://github.com/Gabriel439/nix-diff#readme
  Repository: https://github.com/Gabriella439/nix-diff

  Summary:
    * Highlights what changed between two store paths, including differing dependencies and build flags.
    * Useful for regression analysis when updating packages or tweaking build options.
*/
_:
let
  NixDiffModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."nix-diff".extended;
    in
    {
      options.programs.nix-diff.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nix-diff.";
        };

        package = lib.mkPackageOption pkgs "nix-diff" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nix-diff = NixDiffModule;
}
