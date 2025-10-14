{
  config,
  lib,
  ...
}:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role system.display.x11)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

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

  x11Apps = [
    "colord"
    "gnome-themes-extra"
    "gtk+3"
    "gtk4"
    "gstreamer-vaapi"
    "qt5ct"
    "qt6ct"
    "rtkit"
    "gvfs"
    "i3"
    "i3lock"
    "i3lock-color"
    "i3status"
    "i3status-rust"
    "iceauth"
    "imagemagick"
    "lightdm"
    "pipewire"
    "wireplumber"
    "arandr"
    "autotiling-rs"
    "desktop-file-utils"
    "dmenu"
    "dunst"
    "hsetroot"
    "lxsession"
    "maim"
    "picom"
    "rofi"
    "setxkbmap"
    "sound-theme-freedesktop"
    "speech-dispatcher"
    "xfce4-power-manager"
    "xfce4-settings"
    "xauth"
    "xbacklight"
    "xclip"
    "xdg-desktop-portal"
    "xdg-desktop-portal-gtk"
    "xf86-input-evdev"
    "xf86-input-libinput"
    "xhost"
    "xinput"
    "xlsclients"
    "xkill"
    "xorg-server"
    "xprop"
    "xrandr"
    "xrdb"
    "xset"
    "xsetroot"
    "xterm"
  ];
  roleImports = [ i3SessionModule ] ++ getApps x11Apps;
in
{
  flake.nixosModules.roles.system.display.x11 = {
    metadata = {
      canonicalAppStreamId = "System";
      categories = [ "System" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = roleImports;
  };
}
