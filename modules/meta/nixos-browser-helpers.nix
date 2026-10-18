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
            "_class"
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

  availableBrowsers = flattenBrowsers config.flake.nixosModules.browsers;

  helpers = rec {
    hasBrowser = name: availableBrowsers ? ${name};

    getBrowser = name: availableBrowsers.${name} or (throw "Unknown NixOS browser '${name}'");

    getBrowsers = names: map getBrowser names;

    getAllBrowsers = lib.attrValues availableBrowsers;

    getBrowserOr = name: default: availableBrowsers.${name} or default;
  };
in
{
  _module.args.nixosBrowserHelpers = helpers;

  flake.lib.nixosBrowsers = helpers;

}
