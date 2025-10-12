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
        "_file"
        "imports"
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
                visited = res.visited;
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

  toModuleList = attrs: lib.attrValues attrs;

  modules = flakeModules;
  profileAttrPath = [
    "profiles"
    profileName
  ];
  profileModule = lib.attrByPath profileAttrPath null modules;
  rolesModule = lib.attrByPath [ "roles" ] { } modules;

  roleMap = flattenRoles rolesModule;
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
                    if builtins.elem module roleValues then
                      null
                    else
                      {
                        inherit idx module;
                      }
                  ) importsValue;
                in
                map (
                  entry:
                  "profiles.${profileName}.imports[${toString entry.idx}] does not refer to a roles.* module (found ${describeModule entry.module})"
                ) (lib.filter (entry: entry != null) nonRoleModules);
          in
          lib.optional (disallowedKeys != [ ]) (
            "profiles.${profileName} defines unsupported keys: ${disallowedList}"
          )
          ++ importsErrors;
    in
    baseErrors;
in
{
  valid = errors == [ ];
  inherit errors roleMap;
}
