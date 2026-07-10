{
  flake.nixosModules.hosts-common.imports = [
    (
      { lib, pkgs, ... }:
      {
        boot = {
          # linux-zen: low-latency desktop kernel, prebuilt in cache.nixos.org.
          kernelPackages = lib.mkDefault pkgs.linuxPackages_zen;

          tmp.useTmpfs = true;
          tmp.tmpfsSize = "90%";

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

          # CPU virtualization and monitoring
          kernelModules = [
            "kvm-intel" # Intel VT-x virtualization
            "coretemp" # CPU temperature monitoring
          ];

          # Loader skeleton; each host sets
          # boot.loader.systemd-boot.configurationLimit in hardware-config.nix.
          loader = {
            systemd-boot = {
              enable = true;
              editor = false;
              consoleMode = "auto";
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
      }
    )
  ];
}
