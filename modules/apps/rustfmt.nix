/*
  Package: rustfmt
  Description: Official code formatter for the Rust programming language.
  Homepage: https://github.com/rust-lang/rustfmt
  Documentation: https://rust-lang.github.io/rustfmt/
  Repository: https://github.com/rust-lang/rustfmt

  Summary:
    * Formats Rust source files according to community conventions with stable style guarantees.
    * Integrates with editors, CI pipelines, and `cargo fmt` for consistent codebases.

  Example Usage:
    * `rustfmt src/main.rs` — Format a specific Rust file in place.
    * `cargo fmt` — Format every Rust file in the current workspace.
*/

{
  flake.nixosModules.apps.rustfmt =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rustfmt ];
    };

}
