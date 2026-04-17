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

      hardware = {
        bluetooth = {
          enable = true;
          powerOnBoot = true;
        };

        graphics.extraPackages = [
          pkgs.nvidia-vaapi-driver
          pkgs.vulkan-validation-layers
        ];

        nvidia = {
          package = config.boot.kernelPackages.nvidiaPackages.production;
          modesetting.enable = true;
          open = false;
          gsp.enable = true;
          powerManagement.enable = true;
          powerManagement.finegrained = false;
          nvidiaSettings = true;

          prime = {
            offload.enable = lib.mkForce false;
            sync.enable = true;
            intelBusId = "PCI:0:2:0";
            nvidiaBusId = "PCI:1:0:0";
          };
        };

        nvidia-container-toolkit.enable = true;
      };

      security.rtkit.enable = true;

      environment.systemPackages = with pkgs; [
        mesa-demos
        vulkan-tools
      ];

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
          videoDrivers = lib.mkForce [ "nvidia" ];
          screenSection = lib.mkDefault ''
            Option "metamodes" "nvidia-auto-select +0+0 {ForceFullCompositionPipeline=On}"
          '';
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
