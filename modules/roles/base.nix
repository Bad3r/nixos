{
  config,
  lib,
  ...
}:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role base)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);
  baseModule =
    if lib.hasAttrByPath [ "base" ] config.flake.nixosModules then
      lib.getAttrFromPath [ "base" ] config.flake.nixosModules
    else
      throw "flake.nixosModules.base missing while constructing roles.base";
  baseApps = [
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
  roleImports = [ baseModule ] ++ getApps baseApps;
in
{
  flake.nixosModules.roles.base.imports = roleImports;
}
