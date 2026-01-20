{ config, lib, ... }:
let
  extraAppNames = [
    "bitwarden-desktop"
    "bun"
    "claude-code"
    # "copyq"
    "dive"
    "docker-compose"
    "element-desktop"
    "espanso"
    # "evince"
    "fd"
    "google-chrome"
    "feh"
    "file-roller"
    "firefox"
    "flameshot"
    "floorp"
    "gptfdisk"
    "i3-config"
    "keepassxc"
    "kitty"
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
    "skim"
    # "slack"
    "sqlite"
    "stylix-gui"
    "tree"
    "usbguard-notifier"
    "wezterm"
    "zathura"
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
