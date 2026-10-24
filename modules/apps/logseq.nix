/*
  Package: logseq
  Description: Knowledge management and collaboration tool
  Homepage: https://logseq.com/
  Documentation: https://docs.logseq.com/
  Repository: https://github.com/logseq/logseq

  Summary:
    * A privacy-first, open-source platform for knowledge sharing and management.
    * Supports outlining, note-taking, and graph visualization.

  Options:
    logseq: Launch the desktop application.

  Example Usage:
    * `logseq` -- Open the Logseq desktop app.
*/
{ inputs, ... }:
let
  LogseqModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.logseq.extended;
      cacheSubstituter = "https://nix-logseq-git-flake.cachix.org";
      cachePublicKey = "nix-logseq-git-flake.cachix.org-1:DSBNW07PSRyCvS926tpIWahb53OIydwwZhsP6LhJNZo=";
      basePackage = inputs.nix-logseq-git-flake.packages.${pkgs.stdenv.hostPlatform.system}.logseq;
    in
    {
      options.programs.logseq.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Logseq.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = basePackage;
          description = "The Logseq package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        nix.settings.extra-substituters = lib.mkAfter [ cacheSubstituter ];
        nix.settings.extra-trusted-public-keys = lib.mkAfter [ cachePublicKey ];

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.logseq = LogseqModule;
}
