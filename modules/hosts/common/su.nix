{ config, lib, ... }:
let
  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;
  body = {
    environment.shellAliases.su = "su -p";

    security.pam.services = {
      su = {
        setEnvironment = true;
        sshAgentAuth = true;
      };
      su-l = {
        setEnvironment = true;
        sshAgentAuth = true;
      };
    };
  };
in
{
  configurations.nixos.system76.module = lib.mkIf s76Share body;
  configurations.nixos.tpnix.module = lib.mkIf tpShare body;
}
