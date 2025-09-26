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
    if lib.hasAttrByPath [ "roles" "base" ] config.flake.nixosModules then
      [ (resolveRole "base") ]
    else if lib.hasAttrByPath [ "base" ] config.flake.nixosModules then
      [ (lib.getAttrFromPath [ "base" ] config.flake.nixosModules) ]
    else
      throw "flake.nixosModules.base missing while constructing workstation bundle";
in
{
  flake.nixosModules.workstation.imports = baseImport ++ map resolveRole workstationRoles;
}
