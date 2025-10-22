{ lib, ... }:
let
  homeDir = ./../home;
  homeManagerDir = ./../home-manager;
  hmAppsDir = ./../hm-apps;

  listFiles =
    dir:
    let
      entries = builtins.readDir dir;
    in
    builtins.filter (name: entries.${name} == "regular" && lib.hasSuffix ".nix" name) (
      builtins.attrNames entries
    );

  importFiles = dir: names: map (name: import (dir + "/${name}")) names;

  homeModules = importFiles homeDir (listFiles homeDir);
  homeManagerModules = importFiles homeManagerDir (
    builtins.filter (name: name != "checks.nix") (listFiles homeManagerDir)
  );
  hmAppModules = importFiles hmAppsDir (listFiles hmAppsDir);

  baseImports = homeModules ++ homeManagerModules ++ hmAppModules;
in
{
  flake.homeManagerModules.base = lib.mkOverride 1200 {
    _file = "nixos-home-manager-collect";
    imports = baseImports;
  };
}
