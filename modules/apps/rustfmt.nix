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
_:
let
  RustfmtModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.rustfmt.extended;
    in
    {
      options.programs.rustfmt.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable rustfmt.";
        };

        package = lib.mkPackageOption pkgs "rustfmt" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.rustfmt = RustfmtModule;
}
