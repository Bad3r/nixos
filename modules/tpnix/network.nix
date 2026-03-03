{ lib, ... }:
{
  configurations.nixos.tpnix.module = {
    networking = {
      networkmanager.enable = true;
      useDHCP = lib.mkDefault true;
      firewall = {
        enable = true;
        allowedTCPPorts = [ 22 ];
        allowedUDPPorts = [ ];
      };
    };
  };
}
