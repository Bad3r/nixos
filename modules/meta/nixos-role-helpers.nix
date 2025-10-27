{
  lib,
  config,
  inputs,
  ...
}:
let
  sanitizeModule =
    module:
    if module == null then
      null
    else if lib.isFunction module then
      module
    else if builtins.isAttrs module then
      let
        cleaned =
          let
            stripped = builtins.removeAttrs module [
              "_file"
              "imports"
            ];
          in
          stripped;
        imported = module.imports or [ ];
        sanitizedImports = lib.filter (m: m != null) (map sanitizeModule imported);
      in
      cleaned
      // lib.optionalAttrs (sanitizedImports != [ ]) {
        imports = sanitizedImports;
      }
    else
      null;

  flattenRoles =
    module:
    if module == null then
      { }
    else if lib.isFunction module then
      { }
    else if builtins.isAttrs module then
      let
        direct = lib.filterAttrs (
          name: _:
          !(lib.elem name [
            "_file"
            "imports"
          ])
        ) module;
        sanitizedDirect = lib.mapAttrs (
          name: value: if name == "flake" then value else sanitizeModule value
        ) direct;
        imported = module.imports or [ ];
        merge = acc: value: acc // flattenRoles value;
        merged = lib.foldl' merge sanitizedDirect (
          if builtins.isList imported then imported else [ imported ]
        );
      in
      merged
    else
      { };

  availableRoles =
    let
      fromConfig =
        if
          config ? flake
          && config.flake ? nixosModules
          && lib.hasAttrByPath [ "roles" ] config.flake.nixosModules
        then
          let
            roles = flattenRoles config.flake.nixosModules.roles;
          in
          roles
        else
          { };
      fromSelf =
        let
          selfModules = (inputs.self.outputs or { }).nixosModules or { };
        in
        if lib.hasAttrByPath [ "roles" ] selfModules then
          let
            roles = flattenRoles (lib.getAttrFromPath [ "roles" ] selfModules);
          in
          roles
        else
          { };
    in
    fromConfig // fromSelf;

  roleHelpers = rec {
    hasRole = name: builtins.hasAttr name availableRoles;

    getRole =
      name:
      if hasRole name then
        builtins.getAttr name availableRoles
      else
        let
          previewList = lib.take 20 (lib.attrNames availableRoles);
          preview = lib.concatStringsSep ", " previewList;
          ellipsis = if lib.length previewList == 20 then ", …" else "";
          suggestion = if availableRoles == { } then "" else " Known roles (partial): ${preview}${ellipsis}";
        in
        throw ("Unknown NixOS role '" + name + "'" + suggestion);

    getRoles = names: map getRole names;

    getRoleOr = name: default: if hasRole name then getRole name else default;
  };

in
{
  _module.args.nixosRoleHelpers = roleHelpers;
  flake.lib.nixos.roles = roleHelpers;
}
