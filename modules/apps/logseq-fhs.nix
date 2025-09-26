/*
  Package: logseq-fhs
  Description: FHS-wrapped build of Logseq, the local-first knowledge graph and outliner.
  Homepage: https://logseq.com/
  Documentation: https://docs.logseq.com/
  Repository: https://github.com/logseq/logseq

  Summary:
    * Packages Logseq within an FHS environment so Electron dependencies expecting traditional paths function correctly on NixOS.
    * Enables journaling, graph-based note taking, and Markdown/Org-mode interop with plugins and sync capabilities.

  Options:
    logseq: Launch the Logseq desktop application from the wrapped environment.
    (Further configuration happens through the Logseq UI and settings panels.)

  Example Usage:
    * `logseq` — Open your knowledge graph with the FHS wrapper ensuring compatibility.
    * Configure graph locations and plugin marketplace via Logseq’s settings dialog.
*/

{
  inputs,
  lib,
  ...
}:
let
  inherit (lib) substring;

  logseqRev = inputs.logseq.rev or "main";
  logseqVersion = "unstable-" + substring 0 8 logseqRev;
  logseqSrc = inputs.logseq;

  mkLogseqPackages =
    pkgs:
    (pkgs.callPackage ../../packages/logseq-fhs {
      prefetchYarnDeps = pkgs.prefetch-yarn-deps;
    })
      {
        inherit logseqSrc;
        version = logseqVersion;
        electronPackage = pkgs.electron_37;
      };

  logseqAppModule =
    { pkgs, ... }:
    let
      logseqPackages = mkLogseqPackages pkgs;
    in
    {
      environment.systemPackages = [
        logseqPackages."logseq-fhs"
      ];
    };
in
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        "logseq-fhs" = (mkLogseqPackages pkgs)."logseq-fhs";
        "logseq-fhs-unwrapped" = (mkLogseqPackages pkgs)."logseq-unwrapped";
      };
    };

  flake = {
    nixosModules = {
      apps = {
        logseqFhs = logseqAppModule;
        "logseq-fhs" = logseqAppModule;
      };

      workstation =
        { pkgs, ... }:
        {
          environment.systemPackages = [
            (mkLogseqPackages pkgs)."logseq-fhs"
          ];
        };
    };
  };
}
