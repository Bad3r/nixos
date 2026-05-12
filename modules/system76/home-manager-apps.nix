{ config, lib, ... }:
let
  hostAppNames = [
    "awscli2"
    "pentesting-devshell"
  ];
  flakeHmApps = config.flake.homeManagerModules.apps;
  getAppModule =
    name:
    flakeHmApps.${name}
      or (throw "Home Manager app module '${name}' not found in flake.homeManagerModules.apps");
  hostAppModules = map getAppModule hostAppNames;
in
{
  configurations.nixos.system76.module = _: {
    config = {
      home-manager.extraAppImports = lib.mkAfter hostAppNames;
      home-manager.sharedModules = lib.mkAfter hostAppModules;
    };
  };
}
