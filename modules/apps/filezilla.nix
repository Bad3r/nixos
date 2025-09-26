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
    --locales=LANG: Override the desktop locale (normally autotected via environment variables).
    --config-dir=PATH: Use an alternate configuration directory for bookmarks and settings.
    --help: Display CLI flags and exit.
*/

{
  flake.nixosModules.apps.filezilla =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.filezilla ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.filezilla ];
    };
}
