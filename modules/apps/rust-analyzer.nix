/*
  Package: rust-analyzer
  Description: Language Server Protocol implementation for Rust.
  Homepage: https://rust-analyzer.github.io/
  Documentation: https://rust-analyzer.github.io/manual.html
  Repository: https://github.com/rust-lang/rust-analyzer

  Summary:
    * Powers editor features such as completions, inline type hints, go-to-definition, and refactorings for Rust projects.
    * Leverages `cargo metadata` and incremental analysis to keep responses fast even in larger workspaces.

  Example Usage:
    * `rust-analyzer analysis-stats` — Inspect analysis metrics for the current crate graph.
    * Automatically launched by editors like Neovim, VS Code, and Helix when opening Rust files.
*/

{
  flake.nixosModules.apps."rust-analyzer" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rust-analyzer ];
    };

}
