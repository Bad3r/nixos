{
  lib,
  config,
  inputs,
  ...
}:
let
  sanitizeFlake =
    flakeAttrs:
    if flakeAttrs == null || !(builtins.isAttrs flakeAttrs) then
      null
    else
      let
        sanitizeModules =
          modules:
          if modules == null then
            null
          else if builtins.isAttrs modules then
            lib.mapAttrs (_: sanitizeModule) modules
          else
            modules;

        sanitizedLib =
          if flakeAttrs ? lib && builtins.isAttrs flakeAttrs.lib then
            let
              allowedLibKeys = [
                "meta"
                "nixos"
                "roleExtras"
              ];
            in
            lib.filterAttrs (name: _: lib.elem name allowedLibKeys) flakeAttrs.lib
          else
            null;

        result = {
          homeManagerModules = sanitizeModules (flakeAttrs.homeManagerModules or null);
          nixosModules = sanitizeModules (flakeAttrs.nixosModules or null);
        }
        // lib.optionalAttrs (sanitizedLib != null && sanitizedLib != { }) {
          lib = sanitizedLib;
        };

        cleaned = lib.filterAttrs (_: value: value != null) result;
        _trace = builtins.trace (
          "sanitizeFlake: keys -> " + (lib.concatStringsSep "," (builtins.attrNames cleaned))
        ) null;
      in
      lib.seq _trace (if cleaned == { } then null else cleaned);

  sanitizeModule =
    module:
    if module == null then
      null
    else if lib.isFunction module then
      module
    else if builtins.isAttrs module then
      let
        base = builtins.removeAttrs module [
          "flake"
        ];
        flakeValue = if module ? flake then sanitizeFlake module.flake else null;
      in
      base
      // lib.optionalAttrs (flakeValue != null) {
        flake = flakeValue;
      }
    else
      null;

  sanitizeImportValue =
    value:
    if value == null then
      null
    else if lib.isFunction value then
      value
    else if builtins.isAttrs value then
      let
        base = builtins.removeAttrs value [
          "flake"
        ];
        flakeValue = if value ? flake then sanitizeFlake value.flake else null;
      in
      base
      // lib.optionalAttrs (flakeValue != null) {
        flake = flakeValue;
      }
    else
      value;

  flattenImportList =
    values:
    let
      go =
        value:
        if value == null then
          [ ]
        else if builtins.isList value then
          lib.concatMap go value
        else if lib.isFunction value then
          [ value ]
        else if builtins.isAttrs value then
          let
            base = builtins.removeAttrs value [
              "imports"
              "_file"
            ];
            flakeValue = if value ? flake then sanitizeFlake value.flake else null;
            cleaned =
              base
              // lib.optionalAttrs (flakeValue != null) {
                flake = flakeValue;
              };
            nested = go (value.imports or [ ]);
            keep = cleaned != { };
          in
          (if keep then [ cleaned ] else [ ]) ++ nested
        else
          [ ];
    in
    lib.concatMap go values;

  getRawRoleModule =
    path:
    let
      fullPath = [ "roles" ] ++ path;
      fromConfig =
        if
          config ? flake
          && config.flake ? nixosModules
          && lib.hasAttrByPath fullPath config.flake.nixosModules
        then
          lib.getAttrFromPath fullPath config.flake.nixosModules
        else
          null;
      fromSelf =
        let
          outputs = inputs.self.outputs or { };
          modules = outputs.nixosModules or { };
        in
        if fromConfig == null && lib.hasAttrByPath fullPath modules then
          lib.getAttrFromPath fullPath modules
        else
          null;
    in
    if fromConfig != null then fromConfig else fromSelf;

  roleExtraEntries = config.flake.lib.roleExtras or [ ];

  extrasForRole =
    dotted:
    lib.concatMap (
      entry: if (entry ? role) && (entry ? modules) && entry.role == dotted then entry.modules else [ ]
    ) roleExtraEntries;

  rolesDir = ../roles;

  computeImports =
    moduleLookup: path:
    let
      dotted = lib.concatStringsSep "." path;
      rawFromMap = if dotted == "" then null else moduleLookup."${dotted}" or null;
      rawModule = if rawFromMap != null then rawFromMap else getRawRoleModule path;
      filePath = if path == [ ] then null else rolesDir + "/${lib.concatStringsSep "/" path}/default.nix";
      rawFromFile =
        if rawModule != null || filePath == null || !builtins.pathExists filePath then
          null
        else
          let
            appHelpers = config._module.args.nixosAppHelpers or { };
            moduleFun = import filePath;
            args = {
              inherit lib inputs;
              config = {
                flake = {
                  nixosModules = config.flake.nixosModules or { };
                  lib = {
                    nixos = appHelpers;
                    roleExtras = roleExtraEntries;
                  };
                };
                _module = {
                  args = {
                    nixosAppHelpers = appHelpers;
                    inherit inputs;
                  };
                };
              };
            }
            // lib.optionalAttrs (config ? _module && config._module ? args && config._module.args ? pkgs) {
              inherit (config._module.args) pkgs;
            };
            evaluated = moduleFun args;
            rolesAttr =
              if evaluated ? flake && evaluated.flake ? nixosModules then evaluated.flake.nixosModules else { };
          in
          if lib.hasAttrByPath ([ "roles" ] ++ path) rolesAttr then
            lib.getAttrFromPath ([ "roles" ] ++ path) rolesAttr
          else
            null;
      rawEffective = if rawModule != null then rawModule else rawFromFile;
      importsValue = if rawEffective != null && rawEffective ? imports then rawEffective.imports else [ ];
      asList =
        if importsValue == null then
          [ ]
        else if builtins.isList importsValue then
          importsValue
        else
          [ importsValue ];
      sanitizedBase = lib.filter (value: value != null) (map sanitizeImportValue asList);
      sanitizedExtras =
        let
          sanitizedCandidates = map sanitizeImportValue (extrasForRole dotted);
        in
        lib.filter (value: value != null && !(lib.elem value sanitizedBase)) sanitizedCandidates;
    in
    flattenImportList (sanitizedBase ++ sanitizedExtras);

  flattenRoles =
    let
      mergeAttrsets =
        left: right:
        let
          combineValues =
            _: values:
            let
              present = lib.filter (value: value != null) values;
              allAttrs =
                present != [ ] && builtins.all (value: builtins.isAttrs value && !lib.isDerivation value) present;
              allLists = present != [ ] && builtins.all builtins.isList present;
            in
            if present == [ ] then
              null
            else if allAttrs then
              lib.foldl' mergeAttrsets { } present
            else if allLists then
              lib.concatLists present
            else
              lib.last present;
        in
        lib.filterAttrs (_: value: value != null) (
          builtins.zipAttrsWith combineValues [
            left
            right
          ]
        );

      go =
        path: module: visited:
        if module == null then
          {
            result = { };
            modules = { };
            inherit visited;
          }
        else if lib.isFunction module then
          {
            result = { };
            modules = { };
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
            sanitizedWithFlake =
              sanitizedDirect
              // lib.optionalAttrs (module ? flake) {
                flake = sanitizeFlake module.flake;
              };
            imported = module.imports or [ ];
            merge =
              acc: value:
              let
                res = go path value acc.visited;
              in
              {
                result = mergeAttrsets acc.result res.result;
                modules = acc.modules // res.modules;
                inherit (res) visited;
              };
            dotted = if path == [ ] then null else lib.concatStringsSep "." path;
            moduleEntry =
              if dotted == null then
                { }
              else
                {
                  "${dotted}" = module;
                };
            childEntries = lib.foldlAttrs (
              accModules: childName: _:
              let
                childPath = path ++ [ childName ];
                dottedChild = lib.concatStringsSep "." childPath;
                childValue = lib.getAttrFromPath [ childName ] module;
              in
              if dottedChild == "" || childValue == null then
                accModules
              else
                accModules
                // {
                  "${dottedChild}" = childValue;
                }
            ) { } direct;
            acc0 = {
              result = sanitizedWithFlake;
              modules = moduleEntry // childEntries;
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
            modules = { };
            inherit visited;
          };
    in
    module:
    let
      res = go [ ] module { };
    in
    {
      inherit (res) modules;
      tree = res.result;
    };

  flattenRoleMap =
    moduleLookup: attrs:
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
                  sanitizedImports = computeImports moduleLookup newPath;
                  originalModule = if dotted == "" then null else moduleLookup."${dotted}" or null;
                  rawModule = getRawRoleModule newPath;
                  rawFlake =
                    if rawModule != null && rawModule ? flake then
                      rawModule.flake
                    else if originalModule != null && originalModule ? flake then
                      originalModule.flake
                    else
                      value.flake or null;
                  sanitizedFlake = if rawFlake == null then null else sanitizeFlake rawFlake;
                  _traceFlake =
                    if sanitizedFlake != null then
                      builtins.trace (
                        "nixos-role-helpers: role ${dotted} flake keys -> "
                        + (lib.concatStringsSep "," (builtins.attrNames sanitizedFlake))
                      ) null
                    else
                      null;
                  sanitizedFlake' = lib.seq _traceFlake sanitizedFlake;
                  valueWithImports =
                    value
                    // lib.optionalAttrs (sanitizedFlake' != null) {
                      flake = sanitizedFlake';
                    }
                    // lib.optionalAttrs (sanitizedImports != [ ]) {
                      imports = sanitizedImports;
                    };
                in
                if hasMetadata || isLeaf then
                  {
                    "${dotted}" = valueWithImports;
                  }
                else
                  { };
            in
            acc // current // nested
        ) { } attrs;
    in
    go [ ] attrs;

  availableRoles =
    let
      emptyRoles = {
        tree = { };
        modules = { };
      };
      fromConfig =
        if
          config ? flake
          && config.flake ? nixosModules
          && lib.hasAttrByPath [ "roles" ] config.flake.nixosModules
        then
          flattenRoles config.flake.nixosModules.roles
        else
          emptyRoles;
      fromSelf =
        let
          selfModules = (inputs.self.outputs or { }).nixosModules or { };
        in
        if lib.hasAttrByPath [ "roles" ] selfModules then
          flattenRoles (lib.getAttrFromPath [ "roles" ] selfModules)
        else
          emptyRoles;
      combinedModules = fromSelf.modules // fromConfig.modules;
      combinedTree = fromSelf.tree // fromConfig.tree;
    in
    flattenRoleMap combinedModules combinedTree;

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
