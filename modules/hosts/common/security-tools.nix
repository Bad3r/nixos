_:
let
  body = _: {
    security = {
      pam.sshAgentAuth.enable = true;
      polkit.enable = true;
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
