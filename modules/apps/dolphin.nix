/*
  Package: dolphin
  Description: KDE Plasma's file manager with split views, tabs, and remote protocol support.
  Homepage: https://apps.kde.org/dolphin/
  Documentation: https://docs.kde.org/stable5/en/dolphin/dolphin/
  Repository: https://invent.kde.org/system/dolphin

  Summary:
    * Provides configurable panels, split views, version control integration, and network browsing via KIO.
    * Supports search, tagging, and service menus across local and remote storage.

  Options:
    --new-window <url>: Open a new Dolphin window at the specified location.
    --split: Start with the window split into dual panes.
    --select <path>: Focus and select the given file or directory when opening.
    --daemon: Launch Dolphin’s daemon process without showing a window (for preloading).
    --help, --version: Show usage help or the installed version respectively.
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
          description = "Whether to enable Dolphin file manager.";
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
