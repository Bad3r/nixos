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

  xserverRole = lib.attrByPath [ "roles" "xserver" ] config.flake.nixosModules null;
  i3Module = lib.attrByPath [ "window-manager" "i3" ] config.flake.nixosModules null;

  desktopApps = [
    "blueberry"
    "bluetui"
    "bluez"
    "brave"
    "firefox"
    "kcolorchooser"
    "kdiskmark"
    "kiro"
    "kitty"
    "libnotify"
    "mpv"
    "mpv-cheatsheet"
    "mpv-shim-default-shaders"
    "mpv-thumbfast"
    "mpv-with-scripts"
    "network-manager-applet"
    "networkmanager"
    "networkmanager_dmenu"
    "nicotine-plus"
    "nemo"
    "open-in-mpv"
    "pamixer"
    "playerctl"
    "udiskie"
  ];

  roleImports =
    lib.optionals (xserverRole != null) [ xserverRole ]
    ++ lib.optionals (i3Module != null) [ i3Module ]
    ++ getApps desktopApps;
in
{
  flake.nixosModules.roles.desktop = {
    metadata = {
      canonicalAppStreamId = "System";
      categories = [ "System" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = roleImports;
  };
}
