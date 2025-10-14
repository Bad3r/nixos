{
  lib,
  flakeModules,
}:
let
  taxonomy = import ../../lib/taxonomy { inherit lib; };

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

  roleRoot = lib.attrByPath [ "roles" ] null flakeModules;
  flattenedRoles = flattenRoles roleRoot;
  normalizedRoles = flattenRoleMap flattenedRoles;
  roleEntries = lib.attrsToList normalizedRoles;

  checkRole =
    entry:
    let
      roleName = entry.name;
      module = entry.value;
      moduleType = builtins.typeOf module;
      metadata = if builtins.isAttrs module then module.metadata or null else null;
    in
    lib.concatLists [
      (if module == null then [ "Role '${roleName}' resolved to null module" ] else [ ])
      (
        if !(builtins.isAttrs module) then
          [ "Role '${roleName}' must resolve to an attribute set module (got ${moduleType})" ]
        else
          [ ]
      )
      (
        if builtins.isAttrs module && metadata == null then
          [ "Role '${roleName}' is missing `metadata` attribute" ]
        else
          [ ]
      )
      (
        if builtins.isAttrs module && metadata != null then
          let
            result = taxonomy.validateMetadata metadata;
          in
          if result.valid then [ ] else map (err: "Role '${roleName}': ${err}") result.errors
        else
          [ ]
      )
    ];

  roleErrors = lib.concatMap checkRole roleEntries;

  preambleErrors =
    if roleRoot == null then
      [
        "flake.nixosModules.roles is not defined; cannot validate metadata"
      ]
    else if roleEntries == [ ] then
      [
        "No roles discovered under flake.nixosModules.roles; metadata guard cannot run"
      ]
    else
      [ ];

  errors = preambleErrors ++ roleErrors;
in
{
  valid = errors == [ ];
  inherit errors roleEntries;
}
