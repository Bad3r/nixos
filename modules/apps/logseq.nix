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
_:
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
          description = lib.mdDoc "Whether to enable Logseq.";
        };

        package = lib.mkPackageOption pkgs "logseq" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.logseq = LogseqModule;
}
