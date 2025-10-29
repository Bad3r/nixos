/*
  Package: bitwarden-desktop
  Description: Secure and free password manager for all of your devices.
  Homepage: https://bitwarden.com
  Documentation: https://bitwarden.com/help/article/getting-started-desktop/
  Repository: https://github.com/bitwarden/clients

  Summary:
    * Provides an Electron desktop vault with autofill, biometric unlock, secure notes, and password generator features synced via a Bitwarden account.
    * Supports organizations, TOTP codes, file attachments, and offline access with end-to-end encryption.

  Options:
    --args="--proxy-server=<host:port>": Route traffic through a custom proxy (Electron flag).
    --ozone-platform-hint=auto: Enable native Wayland window decorations on Linux compositors.
    --version: Print the installed Bitwarden client version and exit.
    --disable-gpu: Fallback to software rendering for systems with GPU issues.

  Example Usage:
    * `bitwarden` — Open the desktop vault for interactive logins and vault management.
    * `bitwarden --disable-gpu` — Work around GPU driver bugs in headless or virtual machines.
    * `bitwarden --args="--proxy-server=127.0.0.1:8080"` — Point the client at a corporate proxy when required.
*/

{
  flake.homeManagerModules.apps.bitwarden-desktop =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.bitwarden-desktop ];
    };
}
