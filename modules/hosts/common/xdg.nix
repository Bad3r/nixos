{ config, lib, ... }:
let
  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;
  body = {
    xdg = {
      menus.enable = true;
      mime.enable = true;
      # Browser defaults are set by HM browser modules (floorp.nix, etc.)
      # User-level ~/.config/mimeapps.list always overrides system-level
    };
  };
in
{
  configurations.nixos.system76.module = lib.mkIf s76Share body;
  configurations.nixos.tpnix.module = lib.mkIf tpShare body;
}
