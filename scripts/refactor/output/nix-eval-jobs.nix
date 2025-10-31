/*
  Package: nix-eval-jobs
  Description: Parallel evaluator for flake checks and Hydra-style jobsets.
  Homepage: https://github.com/nix-community/nix-eval-jobs
  Documentation: https://github.com/nix-community/nix-eval-jobs#usage
  Repository: https://github.com/nix-community/nix-eval-jobs

  Summary:
    * Spawns multiple evaluator workers to speed up large `nix flake check` or CI pipelines.
    * Exposes Hydra-compatible JSON output for orchestrators.

  Options:
    nix-eval-jobs <flake> --checks: Evaluate all checks for a flake in parallel.
    nix-eval-jobs <flake> --jobsets <file>: Evaluate jobsets defined in a JSON description.

  Example Usage:
    * `nix-eval-jobs .# --checks` — Run all flake checks concurrently.
    * `nix-eval-jobs github:myorg/myflake --workers 8` — Evaluate with eight parallel workers.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nix-eval-jobs.extended;
  NixEvalJobsModule = {
    options.programs.nix-eval-jobs.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable nix-eval-jobs.";
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
