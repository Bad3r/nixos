{ config, lib, ... }:
let
  owner = lib.attrByPath [ "flake" "lib" "meta" "owner" "username" ] null config;
  hmApps = config.flake.homeManagerModules.apps or { };
  getApp =
    name:
    if lib.hasAttr name hmApps then
      lib.getAttr name hmApps
    else
      throw "System76 profile references unknown Home Manager app '${name}'";
  system76HomeApps = [
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
in
lib.mkIf (owner != null) {
  configurations.nixos.system76.module = _: {
    home-manager.users.${owner}.imports = lib.mkAfter (map getApp system76HomeApps);
  };
}
