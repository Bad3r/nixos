{
  config,
  lib,
  ...
}:
let
  inherit (config.flake.lib.meta.owner) username;
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
    if rawResolveRole "base" != null then
      [ (resolveRole "base") ]
    else if lib.hasAttrByPath [ "base" ] config.flake.nixosModules then
      [ (lib.getAttrFromPath [ "base" ] config.flake.nixosModules) ]
    else
      throw "flake.nixosModules.base missing while constructing workstation bundle";
  hmGuiModule =
    let
      hmModules = config.flake.homeManagerModules or { };
    in
    lib.attrByPath [ "gui" ] null hmModules;
in
{
  flake.nixosModules.workstation = {
    imports = baseImport ++ map resolveRole workstationRoles;
    config = lib.mkIf (hmGuiModule != null) {
      home-manager.users.${username}.imports = [ hmGuiModule ];
    };
  };
}
