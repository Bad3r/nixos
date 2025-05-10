# hosts/linux/system76/hardware.nix
{ inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.system76
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sdhci_pci"
    #     "dm_mod" # Required for LUKS
    #     "cryptd" # Cryptsetup support
  ];

  # Intel virtualization module
  boot.kernelModules = [ "kvm-intel" ];

  boot.initrd.luks.devices."luks-555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec".device =
    "/dev/disk/by-uuid/555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec";

  #   Swap LUKS2
  #   environment.etc."secrets/keys/swap.key".source = "/etc/static/secrets/keys/swap.key";
  #   swapDevices = [{
  #     device = "/dev/disk/by-uuid/f2aaec38-2dee-4e40-ab69-cda8ac19f194"; # decrypted swap UUID
  #     encrypted = {
  #       enable = true;
  #       label = "swap";
  #       blkDev = "/dev/disk/by-uuid/a4943de7-b61a-437b-a05a-7f6570a51018"; # Encrypted LUKS UUID
  #       keyFile = "/etc/static/secrets/keys/swap.key";
  #     };
  #   }];

}
