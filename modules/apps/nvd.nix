/*
  Package: nvd
  Description: Nix package diff tool for comparing derivation closures.
  Homepage: https://github.com/vlinkz/nvd
  Documentation: https://github.com/vlinkz/nvd#readme
  Repository: https://github.com/vlinkz/nvd

  Summary:
    * Compares two Nix store closures to show added, removed, or upgraded packages between generations.
    * Supports JSON summaries for integration into CI pipelines and release notes.

  Options:
    --json: Produce machine-readable diff output for integration with CI pipelines.
    --wide: Expand the diff view to include derivation attribute paths.
    --exit-status: Return non-zero exit codes when differences are detected.
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
          description = lib.mdDoc "Whether to enable nvd.";
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
