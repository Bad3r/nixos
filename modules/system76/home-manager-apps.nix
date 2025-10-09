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
    "lazydocker"
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
      enableModuleFor =
        name: if name == "claude-code" then { programs.claude-code.enable = lib.mkDefault true; } else null;
      extraAppModules = map getAppModule extraAppNames;
      extraEnableModules = lib.filter (m: m != null) (map enableModuleFor extraAppNames);
    in
    {
      config = {
        home-manager.extraAppImports = lib.mkAfter extraAppNames;
        home-manager.sharedModules = lib.mkAfter (extraAppModules ++ extraEnableModules);
      };
    };
}
