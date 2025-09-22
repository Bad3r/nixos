{ lib, ... }:
{
  configurations.nixos.system76.module = _: {
    config = {
      home-manager.extraAppImports = lib.mkAfter [
        "bitwarden"
        "copyq"
        "discord"
        "dive"
        "docker-compose"
        "dua"
        "element-desktop"
        "evince"
        "fd"
        "feh"
        "file-roller"
        "flameshot"
        "gimp"
        "gptfdisk"
        "inkscape"
        "keepassxc"
        "krita"
        "lazydocker"
        "libreoffice"
        "ncdu"
        "pcmanfm"
        "ripgrep"
        "ripgrep-all"
        "signal-desktop"
        "skim"
        "slack"
        "sqlite"
        "telegram-desktop"
        "tree"
        "zathura"
        "zoom"
      ];
    };
  };
}
