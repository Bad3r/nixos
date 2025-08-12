{ config, ... }:
{
  configurations.nixos.system76.module = { pkgs, lib, ... }: {
    # Networking
    networking = {
      networkmanager.enable = true;
      firewall = {
        enable = true;
        allowedTCPPorts = [ 22 ]; # SSH if needed
      };
    };
  };
}