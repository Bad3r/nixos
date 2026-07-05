{ lib, config, ... }:
let
  # Flatten the import tree under `flake.nixosModules.browsers` into a simple
  # attribute set of name → module, mirroring nixos-app-helpers.nix so host
  # imports stay fast and avoid probing the module system on every lookup.
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

  flattenBrowsers =
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
        merge = acc: value: acc // flattenBrowsers value;
      in
      lib.foldl' merge sanitizedDirect (if builtins.isList imported then imported else [ imported ])
    else
      { };

  browsersDir = ../browsers;

  baseBrowsers =
    if lib.hasAttrByPath [ "browsers" ] config.flake.nixosModules then
      flattenBrowsers config.flake.nixosModules.browsers
    else
      { };

  browserDirs = builtins.readDir browsersDir;

  # Browsers live in per-browser subdirectories whose NixOS entry point is
  # `<name>/apps.nix`, unlike the flat `modules/apps/*.nix` layout.
  generatedBrowsers = lib.foldlAttrs (
    acc: dirName: dirInfo:
    if dirInfo == "directory" && !(lib.hasPrefix "_" dirName) then
      if builtins.hasAttr dirName baseBrowsers then
        acc
      else
        let
          filePath = browsersDir + "/${dirName}/apps.nix";
          path = [
            "flake"
            "nixosModules"
            "browsers"
            dirName
          ];
        in
        if builtins.pathExists filePath then
          let
            imported = import filePath;
          in
          if lib.hasAttrByPath path imported then
            acc
            // builtins.listToAttrs [
              (lib.nameValuePair dirName (lib.getAttrFromPath path imported))
            ]
          else
            acc
        else
          acc
    else
      acc
  ) { } browserDirs;

  availableBrowsers = baseBrowsers // generatedBrowsers;

  browserKeys = lib.filter (name: name != "_file" && name != "imports") (
    lib.attrNames availableBrowsers
  );

  helpers = rec {
    hasBrowser = name: builtins.hasAttr name availableBrowsers;

    getBrowser =
      name:
      if hasBrowser name then
        builtins.getAttr name availableBrowsers
      else
        let
          maybeFile = browsersDir + "/${name}/apps.nix";
          fallbackModule =
            if builtins.pathExists maybeFile then
              let
                imported = import maybeFile;
                path = [
                  "flake"
                  "nixosModules"
                  "browsers"
                  name
                ];
              in
              if lib.hasAttrByPath path imported then
                lib.getAttrFromPath path imported
              else
                lib.trace "nixos-browser-helpers: browser module missing path ${builtins.concatStringsSep "." path}" null
            else
              lib.trace "nixos-browser-helpers: missing browser file ${toString maybeFile}" null;
          previewList = lib.take 20 browserKeys;
          preview = lib.concatStringsSep ", " previewList;
          ellipsis = if lib.length browserKeys > 20 then ", ..." else "";
          suggestion = if browserKeys == [ ] then "" else " Known keys (partial): ${preview}${ellipsis}";
        in
        if fallbackModule != null then
          lib.trace "nixos-browser-helpers: fallback loaded ${name}" fallbackModule
        else
          throw ("Unknown NixOS browser '" + name + "'" + suggestion);

    getBrowsers = names: map getBrowser names;

    getAllBrowsers = lib.filter (m: m != null) (getBrowsers browserKeys);

    getBrowserOr = name: default: if hasBrowser name then getBrowser name else default;
  };
in
{
  _module.args.nixosBrowserHelpers = helpers;

  flake.lib.nixosBrowsers = helpers;

}
