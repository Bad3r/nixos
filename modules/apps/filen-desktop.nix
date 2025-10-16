/*
  Package: filen-desktop
  Description: Filen graphical desktop client for encrypted cloud file syncing.
  Homepage: https://filen.io/
  Documentation: https://docs.filen.io/
  Repository: https://github.com/FilenCloudDienste/filen-desktop

  Summary:
    * Synchronizes local folders with Filen end-to-end encrypted cloud storage via a desktop tray application.
    * Provides selective sync, bandwidth limits, share management, and cross-platform file versioning.

  Options:
    filen-desktop --start-in-tray: Launch minimized to the system tray.
    filen-desktop --proxy-server=<url>: Route traffic through an HTTP/SOCKS proxy.
    filen-desktop --enable-logging: Emit verbose logs for troubleshooting sync issues.

  Example Usage:
    * `filen-desktop` — Start the GUI client and connect to your Filen account.
    * `filen-desktop --start-in-tray` — Keep the client running in the background while syncing files.
    * Configure selective sync via the Preferences dialog to limit bandwidth and watched folders.
*/

{
  flake.nixosModules.apps."filen-desktop" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."filen-desktop" ];
    };

}
