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
  toList = value: if builtins.isList value then value else [ value ];
  findRoleInModules =
    modules: namePath:
    if namePath == [ ] then
      null
    else
      let
        current = builtins.head namePath;
        rest = builtins.tail namePath;
        matcher = lib.findFirst (
          module: builtins.isAttrs module && builtins.hasAttr current module
        ) null modules;
      in
      if matcher == null then
        null
      else
        let
          value = builtins.getAttr current matcher;
          childModules =
            if builtins.isAttrs value then
              let
                direct = lib.filterAttrs (
                  name: _:
                  !(lib.elem name [
                    "_file"
                    "imports"
                  ])
                ) value;
              in
              map (name: builtins.getAttr name direct) (builtins.attrNames direct)
            else
              [ ];
          importedModules =
            if builtins.isAttrs value && builtins.hasAttr "imports" value then
              toList (value.imports or [ ])
            else
              [ ];
          nextModules = importedModules ++ childModules;
        in
        if rest == [ ] then value else findRoleInModules nextModules rest;
  findRole =
    name:
    let
      path = lib.splitString "." name;
      rootModules = toList (config.flake.nixosModules.roles.imports or [ ]);
    in
    findRoleInModules rootModules path;
  resolveRole =
    name:
    let
      candidate = rawResolveRole name;
      namePath = lib.splitString "." name;
      rolePath = [ "roles" ] ++ namePath;
      importMatch = findRole name;
    in
    if candidate != null then
      candidate
    else if lib.hasAttrByPath rolePath nixosModules then
      lib.getAttrFromPath rolePath nixosModules
    else if importMatch != null then
      importMatch
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
  devLanguageRoles = [
    "dev.nix"
    "dev.py"
    "dev.go"
    "dev.rs"
    "dev.clj"
  ];
  devLanguageModules = map resolveRole devLanguageRoles;
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
