/*
  Package: google-chrome-dev
  Description: Developer preview of Google Chrome with cutting-edge features and experimental APIs.
  Homepage: https://www.google.com/chrome/dev/
  Documentation: https://developer.chrome.com/docs/
  Repository: https://github.com/nix-community/browser-previews

  Summary:
    * Provides early access to Chrome features roughly 9-12 weeks before stable release.
    * Useful for web developers testing new APIs, DevTools features, and browser capabilities.
    * Updates frequently and may contain experimental or unstable functionality.

  Options:
    --enable-features=<feature>: Enable experimental Chrome features.
    --disable-features=<feature>: Disable specific features for testing.
    --enable-logging --v=1: Enable verbose logging for debugging.
    --user-data-dir=<path>: Use a separate profile directory.

  Example Usage:
    * `google-chrome-unstable` - Launch Chrome Dev (the binary is named google-chrome-unstable).
    * `google-chrome-unstable --enable-features=WebGPU` - Test WebGPU support.
    * `google-chrome-unstable --user-data-dir=/tmp/chrome-test` - Isolated testing profile.

  Local Workarounds:
    * Removes duplicate desktop file with broken /usr/bin path (upstream: browser-previews#44).
*/
{ inputs, ... }:
let
  packageFor = system: inputs.browser-previews.packages.${system}.google-chrome-dev;

  GoogleChromeDevModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.google-chrome-dev.extended;
    in
    {
      options.programs.google-chrome-dev.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable Google Chrome Dev (developer preview).";
        };

        package = lib.mkPackageOption pkgs "google-chrome-dev" { };
      };

      config = {
        # Add overlay to make google-chrome-dev available in pkgs
        # Must be unconditional so the package option can resolve
        nixpkgs.overlays = [
          (_final: prev: {
            google-chrome-dev = (packageFor prev.stdenv.hostPlatform.system).overrideAttrs (oldAttrs: {
              postInstall = (oldAttrs.postInstall or "") + ''
                # Workaround for upstream browser-previews#44:
                # Remove unpatched duplicate desktop file with broken /usr/bin path
                rm -f $out/share/applications/com.google.Chrome.unstable.desktop
              '';
            });
          })
        ];

        nixpkgs.allowedUnfreePackages = lib.mkIf cfg.enable [ "google-chrome-dev" ];

        environment.systemPackages = lib.mkIf cfg.enable [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.google-chrome-dev = GoogleChromeDevModule;
}
