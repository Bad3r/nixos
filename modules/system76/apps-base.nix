{ config, lib, ... }:
let
  appsDir = ../apps;
  helpers = config._module.args.nixosAppHelpers or { };
  fallbackGetApp =
    name:
    let
      filePath = appsDir + "/${name}.nix";
    in
    if builtins.pathExists filePath then
      let
        exported = import filePath;
        module = lib.attrByPath [
          "flake"
          "nixosModules"
          "apps"
          name
        ] null exported;
      in
      if module != null then
        module
      else
        throw ("NixOS app '" + name + "' missing expected attrpath in " + toString filePath)
    else
      throw ("NixOS app module file not found: " + toString filePath);
  getApp = helpers.getApp or fallbackGetApp;
  getApps = helpers.getApps or (names: map getApp names);

  baseAppNames = [
    "coreutils"
    "util-linux"
    "procps"
    "psmisc"
    "less"
    "diffutils"
    "patch"
    "file"
    "findutils"
    "gawk"
    "gnugrep"
    "gnused"
    "rip2"
    "which"
    "xclip"
    "xsel"
    "git"
    "bash-completion"
    "zsh-completions"
    "starship"
    "zoxide"
    "atuin"
    "bc"
    "openssl"
    "lsof"
    "pciutils"
    "usbutils"
    "lshw"
    "dmidecode"
  ];
in
{
  configurations.nixos.system76.module.imports = getApps baseAppNames;
}
