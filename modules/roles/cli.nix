{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (cli role)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);
  cliApps = [
    "dragon-drop"
    "kitty"
    "cosmic-term"
    "bottom"
    "htop"
    "sysstat"
    "direnv"
    "nix-direnv"
    "tealdeer"
  ];
  roleImports = getApps cliApps;
in
{
  flake.nixosModules.roles.cli.imports = roleImports;
}
