_: {
  configurations.nixos.system76.module =
    { lib, ... }:
    {
      # Networking
      networking = {
        networkmanager.enable = true;
        useDHCP = lib.mkDefault true; # From old hardware-configuration.nix
        firewall = {
          enable = true;
          allowedTCPPorts = [
            22
            8082
          ]; # SSH if needed
        };
      };
    };
}
