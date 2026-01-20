{ config, lib, ... }:
let
  extraAppNames = [
    "bitwarden-desktop"
    "bun"
    "claude-code"
    # "copyq"
    "discord"
    "dive"
    "docker-compose"
    "dua"
    "element-desktop"
    "espanso"
    # "evince"
    "fd"
    "glow"
    "google-chrome"
    "feh"
    "file-roller"
    "firefox"
    "flameshot"
    "floorp"
    # "gimp"
    "gptfdisk"
    "i3-config"
    # "inkscape"
    "keepassxc"
    "kitty"
    # "krita"
    # "libreoffice"
    "mangohud"
    "mpv"
    "ncdu"
    "pcmanfm"
    "ripgrep"
    "rofi"
    "ripgrep-all"
    "nixvim"
    "pentesting-devshell"
    "signal-desktop"
    "skim"
    # "slack"
    "sqlite"
    "stylix-gui"
    "telegram-desktop"
    "tree"
    "usbguard-notifier"
    "wezterm"
    "zathura"
    "zoom"
  ];

  # Access Home Manager app modules from the flake's registered modules
  # This allows modules to be defined anywhere in the codebase
  flakeHmApps = config.flake.homeManagerModules.apps;

  getAppModule =
    name:
    flakeHmApps.${name}
      or (throw "Home Manager app module '${name}' not found in flake.homeManagerModules.apps");

  extraAppModules = map getAppModule extraAppNames;
in
{
  configurations.nixos.system76.module = _: {
    config = {
      home-manager.extraAppImports = lib.mkAfter extraAppNames;
      home-manager.sharedModules = lib.mkAfter extraAppModules;
    };
  };
}
