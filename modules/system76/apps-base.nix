{ config, ... }:
let
  helpers =
    config._module.args.nixosAppHelpers
      or (throw "nixosAppHelpers not available - ensure meta/nixos-app-helpers.nix is imported");
  inherit (helpers) getApps;

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
