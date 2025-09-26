/*
  Package: cargo
  Description: Rust's package manager and build tool for compiling, testing, and publishing crates.
  Homepage: https://www.rust-lang.org/
  Documentation: https://doc.rust-lang.org/cargo/index.html
  Repository: https://github.com/rust-lang/cargo

  Summary:
    * Manages Rust project dependencies, builds, tests, and documentation through a unified workflow.
    * Provides subcommands for running binaries, generating new crates, and publishing artifacts to crates.io or alternative registries.

  Options:
    build: Compile the current package and dependencies (use `--release` for optimized builds).
    run: Build and execute the project's main binary with optional arguments.
    test: Execute unit, integration, and doc tests defined in the crate.
    add: Add dependencies to `Cargo.toml` via the official `cargo-edit` integration.
    publish: Package and upload the crate to a registry when ready for release.

  Example Usage:
    * `cargo new my-app` — Scaffold a new binary crate with default layout.
    * `cargo build --release` — Produce optimized artifacts in `target/release`.
    * `cargo test -- --nocapture` — Run the project's test suite and stream stdout for debugging.
*/

{
  flake.nixosModules.apps.cargo =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cargo ];
    };

}
