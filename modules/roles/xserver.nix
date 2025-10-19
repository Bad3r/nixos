{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      let
        appFile = ../apps + "/${name}.nix";
        imported = if builtins.pathExists appFile then import appFile else null;
        modulePath = [
          "flake"
          "nixosModules"
          "apps"
          name
        ];
      in
      if imported != null && lib.hasAttrByPath modulePath imported then
        lib.getAttrFromPath modulePath imported
      else
        throw ("Unknown NixOS app '" + name + "' (role xserver)");
  getApp = name: if rawHelpers ? getApp then rawHelpers.getApp name else fallbackGetApp name;
  getApps = names: if rawHelpers ? getApps then rawHelpers.getApps names else map getApp names;
  xserverApps = [
    "arandr"
    "autotiling-rs"
    "desktop-file-utils"
    "dmenu"
    "dunst"
    "hsetroot"
    "i3lock-color"
    "i3status-rust"
    "lxsession"
    "maim"
    "picom"
    "rofi"
    "xfce4-power-manager"
    "xfce4-settings"
    "xbacklight"
    "xclip"
    "xkill"
  ];
  roleImports = getApps xserverApps;
in
{
  flake.nixosModules.roles.xserver.imports = roleImports;
}
