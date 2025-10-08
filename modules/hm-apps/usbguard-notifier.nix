/*
  Package: usbguard-notifier
  Description: Desktop notifications for USBGuard policy changes and device events.
  Homepage: https://github.com/Cropi/usbguard-notifier

  Summary:
    * Watches the USBGuard D-Bus API and pops up notifications whenever devices are blocked, allowed, or policy changes occur.
    * Useful on workstations to inform the logged-in user about enforcement decisions without granting full CLI access.
*/

{
  flake.homeManagerModules.apps."usbguard-notifier" =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.usbguard-notifier ];

      systemd.user.services."usbguard-notifier" = {
        Unit = {
          Description = "USBGuard desktop notifier";
          After = [
            "graphical-session.target"
            "dbus.service"
          ];
          Wants = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };

        Service = {
          ExecStart = "${pkgs.usbguard-notifier}/bin/usbguard-notifier";
          Restart = "on-failure";
          RestartSec = 5;
        };

        Install = {
          # default.target coverage starts the notifier in sessions that don't
          # raise graphical-session.target (sway, tty, etc.) while still
          # stopping with the graphical target when available.
          WantedBy = [
            "default.target"
            "graphical-session.target"
          ];
        };
      };

    };
}
