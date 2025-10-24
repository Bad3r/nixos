{ config, lib, ... }:
let
  getAppModule =
    name:
    let
      path = [
        "flake"
        "nixosModules"
        "apps"
        name
      ];
    in
    lib.attrByPath path (throw "Missing NixOS app '${name}' while wiring System76 base toolchain.")
      config;

  getApps = config.flake.lib.nixos.getApps or (names: map getAppModule names);

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
