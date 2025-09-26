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
    "base"
    "xserver"
    "files"
    "dev"
    "media"
    "net"
    "productivity"
    "ai-agents"
    "gaming"
  ];
in
{
  flake.nixosModules.workstation.imports = map getRole workstationRoles;
}
