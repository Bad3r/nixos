/*
  Package: filezilla
  Description: Cross-platform FTP, FTPS, and SFTP client with a tabbed GUI.
  Homepage: https://filezilla-project.org/
  Documentation: https://wiki.filezilla-project.org/
  Repository: https://svn.filezilla-project.org/svn/FileZilla3/

  Summary:
    * Transfers files over FTP, FTPS, and SFTP with dual panes, a site manager, directory comparison, and a transfer queue.

  Options:
    --locales=LANG: Override the desktop locale.
    --config-dir=PATH: Use an alternate configuration directory for bookmarks and settings.
    --help: Display CLI flags and exit.
*/
_:
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
          description = "Whether to enable filezilla.";
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
