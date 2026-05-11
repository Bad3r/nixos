{ config, lib, ... }:
let
  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;
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
  configurations.nixos.system76.module = lib.mkIf s76Share body;
  configurations.nixos.tpnix.module = lib.mkIf tpShare body;
}
