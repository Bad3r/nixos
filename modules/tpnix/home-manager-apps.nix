{ config, lib, ... }:
let
  hostAppNames = [
    "libreoffice"
  ];
  flakeHmApps = config.flake.homeManagerModules.apps;
  getAppModule =
    name:
    flakeHmApps.${name}
      or (throw "Home Manager app module '${name}' not found in flake.homeManagerModules.apps");
  hostAppModules = map getAppModule hostAppNames;
in
{
  configurations.nixos.tpnix.module = _: {
    config = {
      home-manager.extraAppImports = lib.mkAfter hostAppNames;
      home-manager.sharedModules = lib.mkAfter hostAppModules;
    };
  };
}
