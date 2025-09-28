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
  getApp =
    name:
    let
      tryRaw =
        if rawHelpers ? getApp then
          builtins.tryEval (rawHelpers.getApp name)
        else
          {
            success = false;
            value = null;
          };
    in
    if tryRaw.success then tryRaw.value else fallbackGetApp name;
  getApps =
    names:
    if rawHelpers ? getApps then
      let
        attempt = builtins.tryEval (rawHelpers.getApps names);
      in
      if attempt.success then attempt.value else map getApp names
    else
      map getApp names;
  i3SessionModule =
    { pkgs, lib, ... }:
    {
      services = {
        xserver = {
          enable = lib.mkDefault true;
          windowManager.i3 = {
            enable = true;
            package = pkgs.i3-gaps;
          };
          displayManager.lightdm.enable = true;
        };

        displayManager.defaultSession = lib.mkDefault "none+i3";

        "systemd-lock-handler".enable = lib.mkDefault true;
      };
    };
  xserverApps = [
    "arandr"
    "autotiling-rs"
    "blueberry"
    "brave"
    "desktop-file-utils"
    "dmenu"
    "dunst"
    "firefox"
    "hsetroot"
    "i3lock-color"
    "i3status-rust"
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
  roleImports = [ i3SessionModule ] ++ getApps xserverApps;
in
{
  flake.nixosModules.roles.xserver.imports = roleImports;
}
