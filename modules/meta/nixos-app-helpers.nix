{ lib, config, ... }:
let
  # Flatten the import tree under `flake.nixosModules.apps` into a simple
  # attribute set of name → module. This keeps host imports fast and avoids
  # probing the module system on every lookup.
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
            "_class"
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

  availableApps = flattenApps config.flake.nixosModules.apps;

  helpers = rec {
    hasApp = name: availableApps ? ${name};

    getApp = name: availableApps.${name} or (throw "Unknown NixOS app '${name}'");

    getApps = names: map getApp names;

    getAllApps = lib.attrValues availableApps;

    getAppOr = name: default: availableApps.${name} or default;
  };
in
{
  _module.args.nixosAppHelpers = helpers;

  flake.lib.nixos = helpers;

}
