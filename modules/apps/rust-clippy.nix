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
_:
let
  RustClippyModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."rust-clippy".extended;
    in
    {
      options.programs."rust-clippy".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable Rust Clippy.";
        };

        package = lib.mkPackageOption pkgs "clippy" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."rust-clippy" = RustClippyModule;
}
