# Each app's packages/<name> joins pkgs while its row is on; a flake.customOverlays.<name> replaces it.
{ config, lib, ... }:
let
  packagesDir = ../../../packages;

  appPackageNames = lib.filter (
    name:
    config.flake.lib.nixos.hasApp name && builtins.pathExists (packagesDir + "/${name}/default.nix")
  ) (lib.attrNames (builtins.readDir packagesDir));

  appPackageOverlay =
    name:
    { config, lib, ... }:
    {
      config = lib.mkIf config.programs.${name}.extended.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            ${name} = final.callPackage (packagesDir + "/${name}") { };
          })
        ];
      };
    };

  body = {
    imports = lib.attrValues config.flake.customOverlays;
  };
in
{
  flake.customOverlays = lib.genAttrs appPackageNames (name: lib.mkDefault (appPackageOverlay name));

  flake.nixosModules.hosts-common.imports = [ body ];
}
