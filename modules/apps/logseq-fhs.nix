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

_:
let
  logseqVersion = "0.10.14";
  logseqSha256 = "07b0r02qv50ckfkmq5w9r1vnhldg01hffz9hx2gl1x1dq3g39kpz";

  mkLogseqPackages =
    pkgs:
    (pkgs.callPackage ../../packages/logseq-fhs {
      version = logseqVersion;
      sha256 = logseqSha256;
      releaseTag = logseqVersion;
    })
      { };

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
