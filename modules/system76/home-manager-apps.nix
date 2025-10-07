{ lib, ... }:
let
  extraAppNames = [
    "bitwarden"
    "copyq"
    "discord"
    "dive"
    "docker-compose"
    "dua"
    "element-desktop"
    # "evince"
    "fd"
    "feh"
    "file-roller"
    "flameshot"
    # "gimp"
    "gptfdisk"
    # "inkscape"
    "keepassxc"
    # "krita"
    "lazydocker"
    # "libreoffice"
    "ncdu"
    "pcmanfm"
    "ripgrep"
    "ripgrep-all"
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
  configurations.nixos.system76.module =
    _:
    let
      appsDir = ../hm-apps;
      getAppModule =
        name:
        let
          filePath = appsDir + "/${name}.nix";
        in
        if builtins.pathExists filePath then
          let
            imported = import filePath;
            module = lib.attrByPath [ "flake" "homeManagerModules" "apps" name ] null imported;
          in
          if module != null then
            module
          else
            throw ("Home Manager app module '" + name + "' missing expected attrpath in " + toString filePath)
        else
          throw ("Home Manager app module file not found: " + toString filePath);
      extraAppModules = map getAppModule extraAppNames;
    in
    {
      config = {
        home-manager.extraAppImports = lib.mkAfter extraAppNames;
        home-manager.sharedModules = lib.mkAfter extraAppModules;
      };
    };
}
