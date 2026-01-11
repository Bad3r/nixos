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
    * `logseq` — Open the Logseq desktop app.
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
          default = inputs.nix-logseq-git-flake.packages.${pkgs.stdenv.hostPlatform.system}.logseq;
          description = "The Logseq package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.logseq = LogseqModule;
}
