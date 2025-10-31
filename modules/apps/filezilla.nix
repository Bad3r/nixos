/*
  Package: filezilla
  Description: Cross-platform FTP, FTPS, and SFTP client with a tabbed GUI.
  Homepage: https://filezilla-project.org/
  Documentation: https://wiki.filezilla-project.org/
  Repository: https://github.com/filezilla/FileZilla

  Summary:
    * Provides dual-pane transfers, site manager profiles, directory comparison, and synchronized browsing for remote servers.
    * Supports FTP over TLS (FTPS) and SSH File Transfer Protocol (SFTP) with transfer queue monitoring and speed limits.

  Options:
    filezilla: Launch the graphical client.
    --locales=LANG: Override the desktop locale (normally autodetected via environment variables).
    --config-dir=PATH: Use an alternate configuration directory for bookmarks and settings.
    --help: Display CLI flags and exit.

  Example Usage:
    * `filezilla` — Open the client to manage multiple FTP, FTPS, or SFTP sessions with drag-and-drop transfers.
    * `filezilla --config-dir ~/.config/filezilla-work` — Separate work profiles, bookmarks, and queue settings.
    * `filezilla --locales=de_DE` — Force a particular locale when the environment locale is unavailable.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  FilezillaModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.filezilla.extended;
    in
    {
      options.programs.filezilla.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable filezilla.";
        };

        package = lib.mkPackageOption pkgs "filezilla" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.filezilla = FilezillaModule;
}
