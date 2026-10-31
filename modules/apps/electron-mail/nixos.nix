/*
  Package: electron-mail
  Description: Unofficial Electron-based desktop client for ProtonMail and Proton Calendar.
  Homepage: https://github.com/vladimiry/ElectronMail
  Documentation: https://github.com/vladimiry/ElectronMail#readme
  Repository: https://github.com/vladimiry/ElectronMail

  Summary:
    * Wraps the Proton web apps with multi-account support, desktop notifications, and encrypted local storage.

  Options:
    --user-data-dir=<path>: Store application data in a custom directory.
    --proxy-server=<url>: Route Proton connections through an HTTP/SOCKS proxy.
    --password-store=<type>: Select the password storage backend (basic or system keyrings).
    --disable-gpu: Force software rendering.
    --enable-logging: Emit Chromium logs.
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
  flake.nixosModules.apps.electron-mail = ElectronMailModule;
}
