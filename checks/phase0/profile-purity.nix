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
