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
    "base"
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
in
{
  flake.nixosModules.pc.imports = map getRole pcRoles;
}
