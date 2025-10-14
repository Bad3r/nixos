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
      builtins.removeAttrs module [
        "flake"
      ]
    else
      null;

  flattenRoles =
    let
      go =
        module: visited:
        if module == null then
          {
            result = { };
            inherit visited;
          }
        else if lib.isFunction module then
          {
            result = { };
            inherit visited;
          }
        else if builtins.isAttrs module then
          let
            key = if module ? _file then builtins.hashString "sha256" (toString module._file) else null;
            seen = if key != null then visited ? key else false;
            visited' =
              if key != null then
                visited
                // {
                  "${key}" = true;
                }
              else
                visited;
            direct = lib.filterAttrs (
              name: _:
              !(lib.elem name [
                "_file"
                "imports"
                "flake"
              ])
            ) module;
            sanitizedDirect = lib.mapAttrs (_: sanitizeModule) direct;
            imported = module.imports or [ ];
            merge =
              acc: value:
              let
                res = go value acc.visited;
              in
              {
                result = lib.recursiveUpdate acc.result res.result;
                inherit (res) visited;
              };
            acc0 = {
              result = sanitizedDirect;
              visited = visited';
            };
            accFinal =
              if seen then
                acc0
              else if imported == null then
                acc0
              else if builtins.isList imported then
                lib.foldl' merge acc0 imported
              else
                merge acc0 imported;
          in
          accFinal
        else
          {
            result = { };
            inherit visited;
          };
    in
    module: (go module { }).result;

  flattenRoleMap =
    let
      go =
        path: attrs:
        lib.foldlAttrs (
          acc: name: value:
          if value == null || !builtins.isAttrs value then
            acc
          else
            let
              newPath = path ++ [ name ];
              dotted = lib.concatStringsSep "." newPath;
              nestedCandidates = lib.filterAttrs (_: v: builtins.isAttrs v) (
                builtins.removeAttrs value [
                  "metadata"
                  "imports"
                  "flake"
                ]
              );
              nested = go newPath nestedCandidates;
              current =
                let
                  hasMetadata = value ? metadata;
                  children = lib.attrNames nestedCandidates;
                  isLeaf = children == [ ];
                in
                if hasMetadata || isLeaf then
                  {
                    "${dotted}" = value;
                  }
                else
                  { };
            in
            acc // current // nested
        ) { } attrs;
    in
    go [ ];

  availableRoles =
    let
      fromConfig =
        if
          config ? flake
          && config.flake ? nixosModules
          && lib.hasAttrByPath [ "roles" ] config.flake.nixosModules
        then
          flattenRoles config.flake.nixosModules.roles
        else
          { };
      fromSelf =
        let
          selfModules = (inputs.self.outputs or { }).nixosModules or { };
        in
        if lib.hasAttrByPath [ "roles" ] selfModules then
          flattenRoles (lib.getAttrFromPath [ "roles" ] selfModules)
        else
          { };
    in
    flattenRoleMap (fromConfig // fromSelf);

  roleHelpers = rec {
    listRoles = builtins.attrNames availableRoles;

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
