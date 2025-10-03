/*
  Package: wappalyzer-next
  Description: CLI for detecting website technology stacks powered by Wappalyzer fingerprints.
  Homepage: https://github.com/s0md3v/wappalyzer-next

  Summary:
    * Provides the `wappalyzer` command-line utility backed by the latest Wappalyzer dataset.
    * Useful when auditing targets during security assessments or automating reconnaissance workflows.

  Example Usage:
    * `wappalyzer https://example.org` — Enumerate detected technologies for the given URL.
*/

_: {
  flake.homeManagerModules.apps."wappalyzer-next" =
    { pkgs, config, ... }:
    {
      home.packages = [
        config.flake.packages.${pkgs.system}.wappalyzer-next
      ];
    };
}
