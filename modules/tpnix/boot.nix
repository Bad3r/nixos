{ lib, ... }:
{
  configurations.nixos.tpnix.module =
    { pkgs, ... }:
    {
      # Use the standard nixpkgs kernel for this host.
      boot.kernelPackages = lib.mkDefault pkgs.linuxPackages;

      boot = {
        # Base kernel modules for this host class.
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

        # Initrd modules (none required explicitly here)
        initrd.kernelModules = [ ];

        # CPU virtualization and monitoring
        kernelModules = [
          "kvm-intel" # Intel VT-x virtualization
          "coretemp" # CPU temperature monitoring
          "intel_pt" # Intel Processor Trace for perf profiling
        ];

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
