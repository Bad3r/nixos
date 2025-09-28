/*
  Package: nix-diff
  Description: Compares the derivation graphs of two Nix outputs to show semantic differences.
  Homepage: https://github.com/Gabriel439/nix-diff
  Documentation: https://github.com/Gabriel439/nix-diff#readme
  Repository: https://github.com/Gabriel439/nix-diff

  Summary:
    * Highlights what changed between two store paths, including differing dependencies and build flags.
    * Useful for regression analysis when updating packages or tweaking build options.

  Options:
    nix-diff <drv-or-path-A> <drv-or-path-B>: Compare two derivations or store paths.
    nix-diff --stats …: Print a condensed summary of attribute-level changes.

  Example Usage:
    * `nix-diff result drv` — Compare a newly built result against a previous drv path.
    * `nix-diff --stats $(nix build .#pkg1 --print-out-paths) $(nix build .#pkg2 --print-out-paths)` — Summarize differences between two builds.
*/

{
  flake.nixosModules.apps."nix-diff" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nix-diff ];
    };
}
