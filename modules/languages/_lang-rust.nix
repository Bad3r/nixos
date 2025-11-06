/*
  Language: Rust
  Description: Systems programming language focused on safety, speed, and concurrency with zero-cost abstractions.
  Homepage: https://www.rust-lang.org/
  Documentation: https://doc.rust-lang.org/
  Repository: https://github.com/rust-lang/rust

  Summary:
    * Provides complete Rust toolchain including compiler (rustc), package manager (cargo), language server (rust-analyzer), linter (clippy), and formatter (rustfmt).
    * Enables memory-safe systems programming with ownership model, preventing data races and null pointer dereferences at compile time.

  Included Tools:
    rustc: Rust compiler with support for multiple targets and optimization levels.
    cargo: Build system and package manager for managing dependencies and building projects.
    rust-analyzer: LSP implementation providing IDE features like completion, goto-definition, and refactoring.
    clippy: Linter providing idiomatic code suggestions and catching common mistakes.
    rustfmt: Code formatter ensuring consistent style across Rust projects.

  Example Usage:
    * `cargo new myproject` — Create a new Rust project with standard structure.
    * `cargo build --release` — Build optimized binary for production.
    * `cargo clippy -- -W clippy::pedantic` — Run linter with extra strict checks.
    * `rustc --edition=2021 main.rs` — Compile single file with specific edition.
*/
_:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.languages.rust.extended;
in
{
  options.languages.rust.extended = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Whether to enable Rust language support.";
    };

    packages = {
      rustc = lib.mkPackageOption pkgs "rustc" { };
      cargo = lib.mkPackageOption pkgs "cargo" { };
      rust-analyzer = lib.mkPackageOption pkgs "rust-analyzer" { };
      clippy = lib.mkPackageOption pkgs "clippy" { };
      rustfmt = lib.mkPackageOption pkgs "rustfmt" { };
    };
  };

  config = lib.mkIf cfg.enable {
    programs = {
      rustc.extended = {
        enable = lib.mkOverride 1050 true;
        package = cfg.packages.rustc;
      };
      cargo.extended = {
        enable = lib.mkOverride 1050 true;
        package = cfg.packages.cargo;
      };
      "rust-analyzer".extended = {
        enable = lib.mkOverride 1050 true;
        package = cfg.packages.rust-analyzer;
      };
      "rust-clippy".extended = {
        enable = lib.mkOverride 1050 true;
        package = cfg.packages.clippy;
      };
      rustfmt.extended = {
        enable = lib.mkOverride 1050 true;
        package = cfg.packages.rustfmt;
      };
    };
  };
}
