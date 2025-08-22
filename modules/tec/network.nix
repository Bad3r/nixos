{ config, ... }:
{
  configurations.nixos.tec.module =
    { lib, ... }:
    {
      # Enable NetworkManager
      networking.networkmanager.enable = true;

      # DHCP configuration from generated config
      networking.useDHCP = lib.mkDefault true;
      # networking.interfaces.enp44s0.useDHCP = lib.mkDefault true;
      # networking.interfaces.enp45s0.useDHCP = lib.mkDefault true;
      # networking.interfaces.wlo1.useDHCP = lib.mkDefault true;
    };
}
