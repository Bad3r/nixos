/*
  Package: nvd
  Description: Nix package diff tool for comparing derivation closures.
  Homepage: https://github.com/vlinkz/nvd
  Documentation: https://github.com/vlinkz/nvd#readme
  Repository: https://git.sr.ht/~khumba/nvd

  Summary:
    * Compares two Nix store closures to show added, removed, or upgraded packages between generations.

  Options:
    diff: Diff two store paths and their closures.
    list: List packages in a store path's closure.
    history: Show the history of a Nix profile.
*/
_:
let
  NvdModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nvd.extended;
    in
    {
      options.programs.nvd.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nvd.";
        };

        package = lib.mkPackageOption pkgs "nvd" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nvd = NvdModule;
}
