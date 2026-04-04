{ lib, ... }:
{
  configurations.nixos.tpnix.module =
    { pkgs, ... }:
    {
      boot.kernelPackages = lib.mkDefault pkgs.cachyosKernels.linuxPackages-cachyos-latest;

      boot = {
        initrd.availableKernelModules = [
          "xhci_pci"
          "ahci"
          "nvme"
          "thunderbolt"
          "usbhid"
          "uas"
          "usb_storage"
          "sd_mod"
          "sdhci_pci"
        ];

        kernelModules = [
          "kvm-intel"
          "coretemp"
          "intel_pt"
        ];

        loader = {
          systemd-boot = {
            enable = true;
            editor = false;
            consoleMode = "auto";
            configurationLimit = 5;
          };
          efi.canTouchEfiVariables = true;
        };

        crashDump = {
          enable = true;
          reservedMemory = "512M";
        };

        # Increase kernel log verbosity and allow magic SysRq for crash triage
        kernel.sysctl = {
          "kernel.printk" = "7 4 1 7";
          "kernel.sysrq" = 1;
          "kernel.dmesg_restrict" = 0; # Allow dmesg without sudo
        };
      };
    };
}
