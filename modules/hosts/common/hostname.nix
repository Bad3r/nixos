{ config, lib, ... }:
let
  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;
  bodyFor = hostName: {
    networking.hostName = hostName;
  };
in
{
  configurations.nixos.system76.module = lib.mkIf s76Share (bodyFor "system76");
  configurations.nixos.tpnix.module = lib.mkIf tpShare (bodyFor "tpnix");
}
