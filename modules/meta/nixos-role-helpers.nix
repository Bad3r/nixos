{ lib, config, ... }:
let
  flattenRoles =
    module:
    if builtins.isAttrs module then
      let
        direct = lib.filterAttrs (
          name: _:
          !(lib.elem name [
            "_file"
            "imports"
          ])
        ) module;
        imported = module.imports or [ ];
        merge = acc: value: acc // flattenRoles value;
      in
      lib.foldl' merge direct (if builtins.isList imported then imported else [ imported ])
    else
      { };

  availableRoles =
    if lib.hasAttrByPath [ "roles" ] config.flake.nixosModules then
      flattenRoles config.flake.nixosModules.roles
    else
      { };

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
