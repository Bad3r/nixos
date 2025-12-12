/*
  Package: signal-desktop
  Description: Private messenger with end-to-end encryption for desktop.
  Homepage: https://signal.org/
  Documentation: https://support.signal.org/
  Repository: https://github.com/signalapp/Signal-Desktop

  Summary:
    * End-to-end encrypted messaging with support for text, voice, and video calls.
    * Disappearing messages, sealed sender, and screen security features for privacy.

  Options:
    --use-tray-icon: Start Signal minimized to system tray.
    --enable-features=UseOzonePlatform --ozone-platform=wayland: Enable native Wayland support.
*/
_:
let
  SignalDesktopModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.signal-desktop.extended;
    in
    {
      options.programs.signal-desktop.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable signal-desktop.";
        };

        package = lib.mkPackageOption pkgs "signal-desktop" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.signal-desktop = SignalDesktopModule;
}
