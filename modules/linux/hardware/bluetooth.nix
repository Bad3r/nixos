# modules/linux/hardware/bluetooth.nix
{ pkgs, ... }:

{
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = false;

  # Safe package declaration without self-reference
  environment.systemPackages = with pkgs; [
    blueberry
    #bluez
    #bluez-tools
  ];
}
