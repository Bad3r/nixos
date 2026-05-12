{ config, lib, ... }:
let
  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;
  body = {
    services.openssh.settings = {
      # `flake.nixosModules.ssh` sets PasswordAuthentication to lib.mkDefault
      # false; override at default priority to enable password auth on shared
      # hosts (matches the prior per-host behavior).
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };
in
{
  configurations.nixos.system76.module = lib.mkIf s76Share body;
  configurations.nixos.tpnix.module = lib.mkIf tpShare body;
}
