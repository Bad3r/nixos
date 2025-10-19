{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role desktop)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  xserverRolePath = [ "roles" "xserver" ];
  xserverRole =
    if lib.hasAttrByPath xserverRolePath config.flake.nixosModules then
      lib.getAttrFromPath xserverRolePath config.flake.nixosModules
    else
      throw "Desktop role requires flake.nixosModules.roles.xserver";
  i3ModulePath = [ "window-manager" "i3" ];
  i3Module =
    if lib.hasAttrByPath i3ModulePath config.flake.nixosModules then
      lib.getAttrFromPath i3ModulePath config.flake.nixosModules
    else
      throw "Desktop role requires flake.nixosModules.window-manager.i3";

  desktopApps = [
    "blueberry"
    "brave"
    "firefox"
    "kcolorchooser"
    "kitty"
    "libnotify"
    "normcap"
    "nemo"
    "networkmanagerapplet"
    "pamixer"
    "playerctl"
    "udiskie"
  ];

  roleImports = [ xserverRole i3Module ] ++ getApps desktopApps;
in
{
  flake.nixosModules.roles.desktop.imports = roleImports;
}
