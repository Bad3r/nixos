{ lib, ... }:
{
  configurations.nixos.tpnix.module =
    { pkgs, ... }:
    {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };

      security.rtkit.enable = true;

      services = {
        dbus = {
          enable = true;
          packages = lib.mkAfter [ pkgs.dconf ];
        };

        pipewire = {
          enable = true;
          alsa = {
            enable = true;
            support32Bit = true;
          };
          pulse.enable = true;
        };

        xserver = {
          enable = true;
          videoDrivers = [ "modesetting" ];
          xkb = {
            layout = "us";
            variant = "";
          };
        };

        power-profiles-daemon.enable = true;
        system76-scheduler.enable = lib.mkForce false;
        lact.enable = lib.mkForce false;

        logind.settings.Login = {
          HandlePowerKey = "lock";
          HandleLidSwitch = "suspend";
          HandleLidSwitchExternalPower = "suspend";
          HandleLidSwitchDocked = "suspend";
        };

        journald = {
          storage = "persistent";
          extraConfig = ''
            SystemMaxUse=200M
          '';
        };

        printing.enable = lib.mkForce false;
        fstrim.enable = true;
      };

      systemd.coredump = {
        enable = true;
        extraConfig = ''
          MaxUse=512M
          MaxRetentionSec=3d
        '';
      };

      xdg = {
        menus.enable = true;
        mime.enable = true;
      };

      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        config.common.default = "gtk";
      };
    };
}
