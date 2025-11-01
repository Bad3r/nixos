/*
  Package: rustc
  Description: Rust compiler (rustc) providing stable toolchain binaries and standard library.
  Homepage: https://www.rust-lang.org/
  Documentation: https://doc.rust-lang.org/rustc/index.html
  Repository: https://github.com/rust-lang/rust

  Summary:
    * Compiles Rust source code to machine code, supporting incremental compilation, LTO, sanitizers, and features gated by edition flags.
    * Works with Cargo as the build tool, but can compile standalone files via `rustc` CLI for low-level control.

  Options:
    rustc <file.rs> -o <output>: Compile a single Rust file.
    --edition <2018|2021|2024>: Specify language edition.
    -C opt-level=<0-3|s|z>: Set optimization level.
    -C target=<triple>: Cross-compile to a specific target.
    -Z <flag>: Enable nightly-only experimental options (if using nightly compiler).

  Example Usage:
    * `rustc main.rs -O` — Compile with optimizations, producing `main`.
    * `rustc lib.rs --crate-type=rlib` — Build a reusable Rust library.
    * `RUSTFLAGS="-C target-cpu=native" cargo build --release` — Example of configuring rustc flags via Cargo.
*/
_:
let
  RustcModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.rustc.extended;
    in
    {
      options.programs.rustc.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable rustc.";
        };

        package = lib.mkPackageOption pkgs "rustc" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.rustc = RustcModule;
}
