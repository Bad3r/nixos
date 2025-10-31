/*
  Package: dolphin
  Description: KDE Plasma's file manager with split views, tabs, and remote protocol support.
  Homepage: https://apps.kde.org/dolphin/
  Documentation: https://docs.kde.org/stable5/en/dolphin/dolphin/
  Repository: https://invent.kde.org/system/dolphin

  Summary:
    * Provides a powerful file manager with configurable panels, split views, version control integration, and network browsing via KIO.
    * Supports advanced search, tagging, and service menus so workflows extend across local and remote storage.

  Options:
    --new-window <url>: Open a new Dolphin window at the specified location.
    --split: Start with the window split into dual panes.
    --select <path>: Focus and select the given file or directory when opening.
    --daemon: Launch Dolphin’s daemon process without showing a window (for preloading).
    --help, --version: Show usage help or the installed version respectively.

  Example Usage:
    * `dolphin ~/Downloads` — Open the file manager focused on the Downloads directory.
    * `dolphin --split --new-window /mnt/storage` — Launch a new window with dual panes rooted at `/mnt/storage`.
    * `dolphin --select ~/Documents/report.pdf` — Highlight a specific file inside Dolphin for quick actions.
*/
_:
let
  DolphinModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.dolphin.extended;
    in
    {
      options.programs.dolphin.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable Dolphin file manager.";
        };

        package = lib.mkPackageOption pkgs [ "kdePackages" "dolphin" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.dolphin = DolphinModule;
}
