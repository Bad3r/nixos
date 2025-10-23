{ lib, ... }:
let
  extraAppNames = [
    "bitwarden"
    "claude-code"
    "copyq"
    "discord"
    "dive"
    "docker-compose"
    "dua"
    "element-desktop"
    "espanso"
    # "evince"
    "fd"
    "glow"
    "feh"
    "file-roller"
    "flameshot"
    # "gimp"
    "gptfdisk"
    # "inkscape"
    "keepassxc"
    # "krita"
    # "libreoffice"
    "ncdu"
    "pcmanfm"
    "ripgrep"
    "ripgrep-all"
    "nixvim"
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
in
{
  configurations.nixos.system76.module = _: {
    config = {
      home-manager.extraAppImports = lib.mkAfter extraAppNames;
    };
  };
}
