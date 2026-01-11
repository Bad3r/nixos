/*
  Package: desktop-file-utils
  Description: Tools for validating and updating freedesktop.org .desktop entries and MIME caches.
  Homepage: https://www.freedesktop.org/wiki/Software/desktop-file-utils/
  Documentation: https://www.freedesktop.org/software/desktop-file-utils/desktop-file-utils.html
  Repository: https://gitlab.freedesktop.org/xdg/desktop-file-utils

  Summary:
    * Provides `desktop-file-validate`, `desktop-file-install`, and `update-desktop-database` to keep desktop entries standards-compliant.
    * Helps package builds and system administrators manage application launchers and MIME associations on Linux desktops.

  Options:
    desktop-file-validate <file>: Check a .desktop file for spec compliance and report warnings.
    desktop-file-install --dir=<path> <file>: Install or rewrite desktop entries into a target directory with canonical keys.
    update-desktop-database <dir>: Refresh the MIME-type cache for applications installed under a shared directory.

  Example Usage:
    * `desktop-file-validate share/applications/myapp.desktop` — Confirm that a launcher meets the freedesktop specification.
    * `desktop-file-install --dir=$HOME/.local/share/applications myapp.desktop` — Deploy a tweaked launcher into the per-user application menu.
    * `update-desktop-database ~/.local/share/applications` — Rebuild MIME caches so new launchers appear in desktop menus.
*/
_:
let
  DesktopFileUtilsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."desktop-file-utils".extended;
    in
    {
      options.programs.desktop-file-utils.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable desktop-file-utils.";
        };

        package = lib.mkPackageOption pkgs "desktop-file-utils" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.desktop-file-utils = DesktopFileUtilsModule;
}
