{
  config,
  lib,
  ...
}:
let
  resolveRole =
    name:
    let
      path = [
        "roles"
        name
      ];
    in
    if lib.hasAttrByPath path config.flake.nixosModules then
      lib.getAttrFromPath path config.flake.nixosModules
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
    if lib.hasAttrByPath [ "roles" "base" ] config.flake.nixosModules then
      [ (resolveRole "base") ]
    else if lib.hasAttrByPath [ "base" ] config.flake.nixosModules then
      [ (lib.getAttrFromPath [ "base" ] config.flake.nixosModules) ]
    else
      throw "flake.nixosModules.base missing while constructing pc bundle";
in
{
  flake.nixosModules.pc.imports = baseImport ++ map resolveRole pcRoles;
}
