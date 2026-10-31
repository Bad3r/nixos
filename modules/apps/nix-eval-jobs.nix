/*
  Package: nix-eval-jobs
  Description: Parallel evaluator for flake checks and Hydra-style jobsets.
  Homepage: https://github.com/nix-community/nix-eval-jobs
  Documentation: https://github.com/nix-community/nix-eval-jobs#usage
  Repository: https://github.com/NixOS/nix-eval-jobs

  Summary:
    * Spawns multiple evaluator workers to speed up large `nix flake check` or CI pipelines.
    * Exposes Hydra-compatible JSON output for orchestrators.
*/
_:
let
  NixEvalJobsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."nix-eval-jobs".extended;
    in
    {
      options.programs.nix-eval-jobs.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nix-eval-jobs.";
        };

        package = lib.mkPackageOption pkgs "nix-eval-jobs" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nix-eval-jobs = NixEvalJobsModule;
}
