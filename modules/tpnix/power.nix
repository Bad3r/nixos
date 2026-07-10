{ lib, ... }:
{
  configurations.nixos.tpnix.module =
    {
      config,
      pkgs,
      ...
    }:
    {
      boot.blacklistedKernelModules = [ "nouveau" ];

      gpu.nvidia = {
        enable = true;
        package = config.boot.kernelPackages.nvidiaPackages.production;
        open = false;
        vaapi.backend = "nvidia";
        # PRIME sync with the chassis default bus IDs (PCI:0:2:0 / PCI:1:0:0).
        prime.enable = true;
      };

      hardware = {
        bluetooth = {
          enable = true;
          powerOnBoot = true;
        };

        nvidia.gsp.enable = true;
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
          xkb = {
            layout = "us";
            variant = "";
          };
        };

        power-profiles-daemon.enable = true;
        lact.enable = lib.mkForce false;

        logind.settings.Login = {
          HandlePowerKey = "lock";
          HandleLidSwitch = "suspend";
          HandleLidSwitchExternalPower = "suspend";
          HandleLidSwitchDocked = "ignore";
        };

        fstrim.enable = true;
      };

      xdg = {
        menus.enable = true;
        mime.enable = true;
      };
    };
}
