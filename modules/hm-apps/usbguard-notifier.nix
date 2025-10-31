/*
  Package: usbguard-notifier
  Description: Desktop notifications for USBGuard policy changes and device events.
  Homepage: https://github.com/Cropi/usbguard-notifier

  Summary:
    * Watches the USBGuard D-Bus API and pops up notifications whenever devices are blocked, allowed, or policy changes occur.
    * Useful on workstations to inform the logged-in user about enforcement decisions without granting full CLI access.
*/

{
  flake.homeManagerModules.apps.usbguard-notifier =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.usbguard-notifier.extended;
    in
    {
      options.programs.usbguard-notifier.extended = {
        enable = lib.mkEnableOption "Desktop notifications for USBGuard policy changes and device events.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.usbguard-notifier ];
      };
    };
}
