{ lib, ... }:
let
  body = _: {
    security = {
      pam.sshAgentAuth.enable = true;
      # A default so a host can turn the polkit-gnome agent off; polkit-agent.nix keys off this.
      polkit.enable = lib.mkDefault true;
      apparmor = {
        enable = true;
        killUnconfinedConfinables = true;
      };
    };

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ ];
      allowedUDPPorts = [ ];
    };

    services.fail2ban = {
      enable = true;
      maxretry = 3;
      bantime = "1h";
      bantime-increment = {
        enable = true;
        maxtime = "48h";
      };
    };

    services.clamav = {
      daemon.enable = false;
      updater.enable = false;
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
