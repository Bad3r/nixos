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
