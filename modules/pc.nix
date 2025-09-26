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
      throw "flake.nixosModules.roles missing while constructing pc bundle";
  getRole =
    name:
    if lib.hasAttr name roles then
      lib.getAttr name roles
    else
      throw ("Unknown role '" + name + "' referenced by flake.nixosModules.pc");
  pcRoles = [
    "xserver"
    "files"
    "dev"
    "media"
    "net"
    "productivity"
    "ai-agents"
    "gaming"
    "security"
  ];
  baseImport =
    if lib.hasAttr "base" roles then
      [ (getRole "base") ]
    else if lib.hasAttrByPath [ "base" ] config.flake.nixosModules then
      [ (lib.getAttrFromPath [ "base" ] config.flake.nixosModules) ]
    else
      throw "flake.nixosModules.base missing while constructing pc bundle";
in
{
  flake.nixosModules.pc.imports = baseImport ++ map getRole pcRoles;
}
