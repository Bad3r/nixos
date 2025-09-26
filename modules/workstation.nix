{
  config,
  lib,
  ...
}:
let
  roles =
    if lib.hasAttrByPath [ "roles" ] config.flake.nixosModules then
      config.flake.nixosModules.roles
    else
      throw "flake.nixosModules.roles missing while constructing workstation bundle";
  getRole =
    name:
    if lib.hasAttr name roles then
      lib.getAttr name roles
    else
      throw ("Unknown role '" + name + "' referenced by flake.nixosModules.workstation");
  workstationRoles = [
    "xserver"
    "files"
    "dev"
    "media"
    "net"
    "productivity"
    "ai-agents"
    "gaming"
    "security"
    "cloudflare"
  ];
  baseImport =
    if lib.hasAttr "base" roles then
      [ (getRole "base") ]
    else if lib.hasAttrByPath [ "base" ] config.flake.nixosModules then
      [ (lib.getAttrFromPath [ "base" ] config.flake.nixosModules) ]
    else
      throw "flake.nixosModules.base missing while constructing workstation bundle";
in
{
  flake.nixosModules.workstation.imports = baseImport ++ map getRole workstationRoles;
}
