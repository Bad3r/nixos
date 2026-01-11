/*
  Package: electron-mail
  Description: Unofficial Electron-based desktop client for ProtonMail and Proton Calendar.
  Homepage: https://github.com/vladimiry/ElectronMail
  Documentation: https://github.com/vladimiry/ElectronMail#readme
  Repository: https://github.com/vladimiry/ElectronMail

  Summary:
    * Wraps the Proton web apps in an Electron shell with multi-account support, desktop notifications, and encrypted local storage.
    * Offers configurable proxy, tray, and auto-launch options for cross-platform ProtonMail access.

  Options:
    --user-data-dir=<path>: Store application data in a custom directory.
    --proxy-server=<url>: Route Proton connections through an HTTP/SOCKS proxy.
    --password-store=<type>: Select the password storage backend (basic or system keyrings).
    --disable-gpu: Force software rendering, useful on unsupported graphics stacks.
    --enable-logging: Emit Chromium logs for troubleshooting connection or UI issues.

  Example Usage:
    * `electron-mail --user-data-dir=$HOME/.local/share/electron-mail` — Keep account data under an explicit directory.
    * `electron-mail --proxy-server="socks5://127.0.0.1:1080"` — Tunnel ProtonMail traffic through a local SOCKS proxy.
    * `electron-mail --disable-gpu --enable-logging` — Diagnose rendering problems on hardware with flaky GPU support.
*/
_:
let
  ElectronMailModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."electron-mail".extended;
    in
    {
      options.programs.electron-mail.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable electron-mail.";
        };

        package = lib.mkPackageOption pkgs "electron-mail" { };
      };

      config = lib.mkIf cfg.enable {

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "electron-mail" ];
  flake.nixosModules.apps.electron-mail = ElectronMailModule;
}
