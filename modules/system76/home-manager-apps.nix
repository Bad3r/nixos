{ config, lib, ... }:
let
  extraAppNames = [
    "bitwarden-desktop"
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
    "flameshot"
    "floorp"
    # "gimp"
    "gptfdisk"
    # "inkscape"
    "keepassxc"
    # "krita"
    # "libreoffice"
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
    "telegram-desktop"
    "tree"
    "usbguard-notifier"
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
