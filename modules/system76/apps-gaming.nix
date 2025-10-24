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
  hasApp = helpers.hasApp or (name: builtins.pathExists (appsDir + "/${name}.nix"));

  desiredAppNames = [
    "steam"
    "wine-tools"
    "mangohud"
  ];

  availableAppNames = lib.filter hasApp desiredAppNames;
in
{
  configurations.nixos.system76.module.imports = getApps availableAppNames;
}
