{
  config,
  lib,
  ...
}:
let
  inherit (config.flake.lib.meta.owner) username;
  flakeAttrs = config.flake or { };
  nixosModules = flakeAttrs.nixosModules or { };
  roleHelpers = config._module.args.nixosRoleHelpers or { };
  rawResolveRole = roleHelpers.getRole or (_: null);
  resolveRole =
    name:
    let
      candidate = rawResolveRole name;
      namePath = lib.splitString "." name;
      rolePath = [ "roles" ] ++ namePath;
    in
    if candidate != null then
      candidate
    else if lib.hasAttrByPath rolePath nixosModules then
      lib.getAttrFromPath rolePath nixosModules
    else
      throw ("Unknown role '" + name + "' referenced by flake.nixosModules.workstation");
  workstationRoles = [
    "xserver"
    "cli"
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
  devLanguageModules =
    let
      devAttrset = lib.attrByPath [ "roles" "dev" ] { } nixosModules;
      collectRoleModules =
        attrset: isRoot:
        let
          childAttrs = lib.filterAttrs (_: value: builtins.isAttrs value) attrset;
          childModules = lib.concatMap (child: collectRoleModules child false) (lib.attrValues childAttrs);
          ownModules = if (!isRoot && attrset ? imports) then [ attrset ] else [ ];
        in
        ownModules ++ childModules;
    in
    collectRoleModules devAttrset true;
  baseImport =
    if rawResolveRole "base" != null then
      [ (resolveRole "base") ]
    else if lib.hasAttrByPath [ "base" ] nixosModules then
      [ (lib.getAttrFromPath [ "base" ] nixosModules) ]
    else
      throw "flake.nixosModules.base missing while constructing workstation bundle";
  hmGuiModule =
    let
      hmModules = flakeAttrs.homeManagerModules or { };
    in
    lib.attrByPath [ "gui" ] null hmModules;
in
{
  flake.nixosModules.workstation = {
    imports = baseImport ++ map resolveRole workstationRoles ++ devLanguageModules;
    config = lib.mkIf (hmGuiModule != null) {
      home-manager.users.${username}.imports = [ hmGuiModule ];
    };
  };
}
