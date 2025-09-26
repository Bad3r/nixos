{
  config,
  lib,
  ...
}:
let
  baseModule =
    if lib.hasAttrByPath [ "base" ] config.flake.nixosModules then
      lib.getAttrFromPath [ "base" ] config.flake.nixosModules
    else
      throw "flake.nixosModules.base missing while constructing roles.base";
in
{
  flake.nixosModules.roles.base.imports = [ baseModule ];
}
