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
            9999 # Stash default port
          ];
          allowedTCPPortRanges = [
            {
              from = 8000;
              to = 8999;
            }
          ];
          # Allow SSH from the Tailscale tunnel
          interfaces.tailscale0.allowedTCPPorts = [ 22 ];

          # Allow SSH from local network (10.0.0.0/8)
          extraCommands = ''
            iptables -A nixos-fw -s 10.0.0.0/8 -p tcp --dport 22 -j nixos-fw-accept
          '';
          extraStopCommands = ''
            iptables -D nixos-fw -s 10.0.0.0/8 -p tcp --dport 22 -j nixos-fw-accept || true
          '';
        };
      };
    };
}
