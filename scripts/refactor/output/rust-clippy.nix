/*
  Package: rust-clippy
  Description: Collection of lints to catch common mistakes and improve Rust code.
  Homepage: https://github.com/rust-lang/rust-clippy
  Documentation: https://github.com/rust-lang/rust-clippy#readme
  Repository: https://github.com/rust-lang/rust-clippy

  Summary:
    * Extends the Rust compiler with additional warnings covering correctness, performance, and idiomatic style issues.
    * Runs via `cargo clippy` integrating into existing project workflows and CI pipelines.

  Example Usage:
    * `cargo clippy` — Lint the current Rust workspace with default lint groups.
    * `cargo clippy -- -W clippy::pedantic -A clippy::module-name-repetitions` — Customize lint levels per project needs.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.rustPackages.extended;
  RustPackagesModule = {
    options.programs.rustPackages.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable rustPackages.";
      };

      package = lib.mkPackageOption pkgs "rustPackages" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.rustPackages = RustPackagesModule;
}
