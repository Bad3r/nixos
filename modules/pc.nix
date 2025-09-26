{
  config,
  lib,
  ...
}:
let
  roleHelpers = config._module.args.nixosRoleHelpers or { };
  rawResolveRole = roleHelpers.getRole or (_: null);
  resolveRole =
    name:
    let
      candidate = rawResolveRole name;
    in
    if candidate != null then
      candidate
    else if lib.hasAttrByPath [ "roles" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "roles" name ] config.flake.nixosModules
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
    if rawResolveRole "base" != null then
      [ (resolveRole "base") ]
    else if lib.hasAttrByPath [ "base" ] config.flake.nixosModules then
      [ (lib.getAttrFromPath [ "base" ] config.flake.nixosModules) ]
    else
      throw "flake.nixosModules.base missing while constructing pc bundle";
in
{
  flake.nixosModules.pc.imports = baseImport ++ map resolveRole pcRoles;
}
