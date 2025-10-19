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

  roleHelpers = config._module.args.nixosRoleHelpers or { };
  rawRoleHelpers = (config.flake.lib.nixos.roles or { }) // roleHelpers;
  fallbackGetRole =
    name:
    let
      filePath = ../roles + "/${name}.nix";
      imported = if builtins.pathExists filePath then import filePath else null;
      modulePath = [
        "flake"
        "nixosModules"
        "roles"
        name
      ];
    in
    if imported != null && lib.hasAttrByPath modulePath imported then
      lib.getAttrFromPath modulePath imported
    else
      throw ("Desktop role requires flake.nixosModules.roles." + name);
  getRole = rawRoleHelpers.getRole or fallbackGetRole;
  xserverRole = getRole "xserver";

  getWindowManagerModule =
    name:
    let
      filePath = ../window-manager + "/${name}.nix";
      imported = if builtins.pathExists filePath then import filePath else null;
      modulePath = [
        "flake"
        "nixosModules"
        "window-manager"
        name
      ];
    in
    if imported != null && lib.hasAttrByPath modulePath imported then
      lib.getAttrFromPath modulePath imported
    else
      throw ("Desktop role requires flake.nixosModules.window-manager." + name);
  i3Module = getWindowManagerModule "i3";

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

  roleImports = [
    xserverRole
    i3Module
  ]
  ++ getApps desktopApps;
in
{
  flake.nixosModules.roles.desktop.imports = roleImports;
}
