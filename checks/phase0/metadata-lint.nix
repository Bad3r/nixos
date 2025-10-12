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
      let
        cleaned = builtins.removeAttrs module [
          "_file"
          "imports"
          "flake"
        ];
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
        sanitizedDirect = lib.mapAttrs (_: sanitizeModule) direct;
        imported = module.imports or [ ];
        merge = acc: value: acc // flattenRoles value;
        flattenedImports =
          if builtins.isList imported then lib.foldl' merge { } imported else flattenRoles imported;
      in
      lib.foldl' merge sanitizedDirect [ flattenedImports ]
    else
      { };

  roleRoot = lib.attrByPath [ "roles" ] null flakeModules;
  flattenedRoles = flattenRoles roleRoot;
  roleEntries = lib.attrsToList flattenedRoles;

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
