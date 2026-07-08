/*
  Package: google-chrome
  Description: Freeware web browser developed by Google.
  Homepage: https://www.google.com/chrome/
  Documentation: https://support.google.com/chrome/

  Local Workarounds:
    * Removes the duplicate com.google.Chrome.desktop launcher entry. nixpkgs
      patches its Exec path, so it is a working duplicate of
      google-chrome.desktop, not a broken one; dropping it avoids two
      identical "Google Chrome" menu entries.

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
    * `google-chrome-stable` -- Launch Google Chrome (the binary is named google-chrome-stable).
    * `google-chrome-stable --enable-features=WebGPU` -- Test WebGPU support.
    * `google-chrome-stable --user-data-dir=/tmp/chrome-test` -- Isolated testing profile.
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

      inherit (import ../_chromium-policies.nix)
        managedExtensionSettings
        managedDefaultSearchProvider
        ;
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
        nixpkgs.overlays = [
          (_final: prev: {
            google-chrome = prev.google-chrome.overrideAttrs (oldAttrs: {
              postInstall = (oldAttrs.postInstall or "") + ''
                # nixpkgs patches this file's Exec path, so it duplicates
                # google-chrome.desktop; drop it to avoid a second launcher.
                rm -f $out/share/applications/com.google.Chrome.desktop
              '';
            });
          })
        ];

        environment.systemPackages = [ cfg.package ];

        environment.etc = {
          "opt/chrome/policies/managed/extension-settings.json".text = builtins.toJSON {
            ExtensionSettings = managedExtensionSettings;
          };
          "opt/chrome/policies/managed/default-search-provider.json".text =
            builtins.toJSON managedDefaultSearchProvider;
        };
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "google-chrome" ];
  flake.nixosModules.browsers.google-chrome = GoogleChromeModule;
}
