{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role xserver)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);
  xserverApps = [
    "arandr"
    "autotiling-rs"
    "blueberry"
    "brave"
    "cosmic-term"
    "desktop-file-utils"
    "dmenu"
    "dolphin"
    "dunst"
    "firefox"
    "hsetroot"
    "i3lock-color"
    "i3status-rust"
    "kitty"
    "libnotify"
    "lxsession"
    "maim"
    "nemo"
    "networkmanagerapplet"
    "pamixer"
    "picom"
    "playerctl"
    "rofi"
    "udiskie"
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
