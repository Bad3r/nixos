{ config, lib, ... }:
let
  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;
  exported = import ../../apps/i3wm/nixos.nix;
  i3Module = lib.getAttrFromPath [
    "flake"
    "nixosModules"
    "window-manager"
    "i3"
  ] exported;
  body = {
    imports = lib.optional (i3Module != null) i3Module;
  };
in
{
  configurations.nixos.system76.module = lib.mkIf s76Share body;
  configurations.nixos.tpnix.module = lib.mkIf tpShare body;
}
