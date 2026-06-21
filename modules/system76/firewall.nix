_: {
  configurations.nixos.system76.module = {
    networking.firewall = {
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
      interfaces.tailscale0.allowedTCPPorts = [ 22 ];
      interfaces."enp4s0" = {
        allowedUDPPorts = [
          53
          67
        ];
        allowedTCPPorts = [ 53 ];
      };
      # Allow SSH from local network (10.0.0.0/8)
      extraCommands = ''
        iptables -A nixos-fw -s 10.0.0.0/8 -p tcp --dport 22 -j nixos-fw-accept
      '';
      extraStopCommands = ''
        iptables -D nixos-fw -s 10.0.0.0/8 -p tcp --dport 22 -j nixos-fw-accept || true
      '';
    };
  };
}
