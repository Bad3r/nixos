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
  flake.nixosModules.apps."rust-clippy" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rustPackages.clippy ];
    };

}
