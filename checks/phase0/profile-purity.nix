{
  lib,
  flakeModules,
  profileName ? "workstation",
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
                result = acc.result // res.result;
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
              segments = lib.filter (seg: seg != "") (lib.splitString "." name);
              newPath = path ++ segments;
              dotted = lib.concatStringsSep "." newPath;
              sanitized = sanitizeModule value;
              nestedCandidates = lib.filterAttrs (_: v: builtins.isAttrs v) (
                builtins.removeAttrs sanitized [
                  "metadata"
                  "imports"
                  "flake"
                ]
              );
              nested = go newPath nestedCandidates;
              current =
                if sanitized ? metadata then
                  {
                    "${dotted}" = sanitized;
                  }
                else
                  { };
            in
            acc // current // nested
        ) { } attrs;
    in
    go [ ];

  toModuleList = attrs: lib.attrValues attrs;

  modules = flakeModules;
  profileAttrPath = [
    "profiles"
    profileName
  ];
  legacyProfileAttrPath = [ profileName ];
  profileModule =
    let
      preferred = lib.attrByPath profileAttrPath null modules;
    in
    if preferred != null then preferred else lib.attrByPath legacyProfileAttrPath null modules;
  rolesModule = lib.attrByPath [ "roles" ] { } modules;

  roleTree = flattenRoles rolesModule;
  roleMap = flattenRoleMap roleTree;
  roleValues = toModuleList roleMap;

  roleIndex = lib.listToAttrs (
    map (name: {
      inherit name;
      value = builtins.getAttr name roleMap;
    }) (lib.attrNames roleMap)
  );

  describeModule =
    module:
    let
      matchingNames = lib.filterAttrs (_: candidate: candidate == module) roleIndex;
      names = lib.attrNames matchingNames;
    in
    if names == [ ] then
      "<non-role module>"
    else
      lib.concatStringsSep ", " (map (name: "roles." + name) names);

  errors =
    let
      baseErrors =
        if profileModule == null then
          [
            "profiles.${profileName} is not defined under flake.nixosModules"
          ]
        else if !(builtins.isAttrs profileModule) then
          [
            "profiles.${profileName} must be an attribute set module (got ${builtins.typeOf profileModule})"
          ]
        else
          let
            allowedKeys = [
              "imports"
              "_file"
            ];
            disallowedKeys = lib.filter (key: !(lib.elem key allowedKeys)) (
              lib.attrNames (builtins.removeAttrs profileModule [ "_file" ])
            );
            importsValue = profileModule.imports or null;
            disallowedList = lib.concatStringsSep ", " disallowedKeys;
            importsErrors =
              if importsValue == null then
                [
                  "profiles.${profileName} must define an `imports` list"
                ]
              else if !(builtins.isList importsValue) then
                [
                  "profiles.${profileName}.imports must be a list (got ${builtins.typeOf importsValue})"
                ]
              else
                let
                  nonRoleModules = lib.imap1 (
                    idx: module:
                    let
                      sanitized = sanitizeModule module;
                      allowedModule =
                        builtins.isAttrs module
                        && (
                          builtins.elem sanitized roleValues
                          || (module ? metadata)
                          || (module ? imports)
                          || (
                            module ? _file
                            && (
                              lib.hasInfix "/modules/workstation" (toString module._file)
                              || lib.hasInfix "/modules/roles" (toString module._file)
                              || lib.hasInfix "/modules/apps" (toString module._file)
                            )
                          )
                        );
                    in
                    if allowedModule then null else { inherit idx module; }
                  ) importsValue;
                in
                map (
                  entry:
                  "profiles.${profileName}.imports[${toString entry.idx}] does not refer to a roles.* module (found ${describeModule entry.module})"
                ) (lib.filter (entry: entry != null) nonRoleModules);
          in
          lib.optional (
            disallowedKeys != [ ]
          ) "profiles.${profileName} defines unsupported keys: ${disallowedList}"
          ++ importsErrors;
    in
    baseErrors;
in
{
  valid = errors == [ ];
  inherit errors roleMap;
}
