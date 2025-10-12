{ lib, config, ... }:
let
  # Flatten the import tree under `flake.nixosModules.apps` into a simple
  # attribute set of name → module. This keeps roles fast and avoids probing the
  # module system on every lookup.
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

  flattenApps =
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
        merge = acc: value: acc // flattenApps value;
      in
      lib.foldl' merge sanitizedDirect (if builtins.isList imported then imported else [ imported ])
    else
      { };

  appsDir = ../apps;

  baseApps =
    if lib.hasAttrByPath [ "apps" ] config.flake.nixosModules then
      flattenApps config.flake.nixosModules.apps
    else
      { };

  appFiles = builtins.readDir appsDir;

  generatedApps = lib.foldlAttrs (
    acc: fileName: fileInfo:
    let
      hasSuffix = lib.hasSuffix ".nix" fileName;
    in
    if fileInfo == "regular" && hasSuffix then
      let
        appName = lib.removeSuffix ".nix" fileName;
      in
      if builtins.hasAttr appName baseApps then
        acc
      else
        let
          filePath = appsDir + "/${fileName}";
          imported = import filePath;
          path = [
            "flake"
            "nixosModules"
            "apps"
            appName
          ];
        in
        if lib.hasAttrByPath path imported then
          acc
          // builtins.listToAttrs [
            (lib.nameValuePair appName (lib.getAttrFromPath path imported))
          ]
        else
          acc
    else
      acc
  ) { } appFiles;

  availableApps = baseApps // generatedApps;

  appKeys = lib.attrNames availableApps;

  helpers = rec {
    hasApp = name: builtins.hasAttr name availableApps;

    getApp =
      name:
      if hasApp name then
        builtins.getAttr name availableApps
      else
        let
          maybeFile = appsDir + "/${name}.nix";
          fallbackModule =
            if builtins.pathExists maybeFile then
              let
                imported = import maybeFile;
                path = [
                  "flake"
                  "nixosModules"
                  "apps"
                  name
                ];
              in
              if lib.hasAttrByPath path imported then
                lib.getAttrFromPath path imported
              else
                lib.trace "nixos-app-helpers: app module missing path ${builtins.concatStringsSep "." path}" null
            else
              lib.trace "nixos-app-helpers: missing app file ${toString maybeFile}" null;
          previewList = lib.take 20 appKeys;
          preview = lib.concatStringsSep ", " previewList;
          ellipsis = if lib.length appKeys > 20 then ", …" else "";
          suggestion = if appKeys == [ ] then "" else " Known keys (partial): ${preview}${ellipsis}";
        in
        if fallbackModule != null then
          lib.trace "nixos-app-helpers: fallback loaded ${name}" fallbackModule
        else
          throw ("Unknown NixOS app '" + name + "'" + suggestion);

    getApps = names: map getApp names;

    getAppOr = name: default: if hasApp name then getApp name else default;
  };
in
{
  _module.args.nixosAppHelpers = helpers;

  flake.lib.nixos = helpers;

}
