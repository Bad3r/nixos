/*
  Package: flake-checker
  Description: Health checks for your Nix flakes.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/DeterminateSystems/flake-checker

  Summary:
    * Checks flake.lock Nixpkgs inputs for freshness, supported refs, and upstream ownership.
    * Supports explicit Common Expression Language policies for repository-specific lockfile rules.

  Options:
    --no-telemetry: Disable aggregate diagnostic reporting.
    --fail-mode: Exit non-zero when the checker finds policy issues.
    --condition <CONDITION>: Apply a CEL policy to each checked Nixpkgs input.
    --nixpkgs-keys <KEY_LIST>: Check a comma-separated list of Nixpkgs input keys.
*/
_:
let
  FlakeCheckerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.flake-checker.extended;
    in
    {
      options.programs.flake-checker.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable flake-checker.";
        };

        package = lib.mkPackageOption pkgs "flake-checker" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.flake-checker = FlakeCheckerModule;
}
