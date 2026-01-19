/*
  Package: google-chrome
  Description: Freeware web browser developed by Google.
  Homepage: https://www.google.com/chrome/
  Documentation: https://support.google.com/chrome/
  Repository: https://github.com/nicotine-plus/nicotine-plus

  Summary:
    * Full-featured web browser with Google account sync, built-in PDF viewer, and automatic updates.
    * Supports Chrome extensions from the Web Store and enterprise policy management.

  Options:
    --enable-features=<feature>: Enable experimental Chrome features.
    --disable-features=<feature>: Disable specific features for testing.
    --enable-logging --v=1: Enable verbose logging for debugging.
    --user-data-dir=<path>: Use a separate profile directory.
    --incognito: Launch directly in incognito mode.

  Example Usage:
    * `google-chrome-stable` — Launch Google Chrome (the binary is named google-chrome-stable).
    * `google-chrome-stable --enable-features=WebGPU` — Test WebGPU support.
    * `google-chrome-stable --user-data-dir=/tmp/chrome-test` — Isolated testing profile.
*/
_:
let
  GoogleChromeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.google-chrome.extended;
    in
    {
      options.programs.google-chrome.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Google Chrome.";
        };

        package = lib.mkPackageOption pkgs "google-chrome" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "google-chrome" ];
  flake.nixosModules.apps.google-chrome = GoogleChromeModule;
}
