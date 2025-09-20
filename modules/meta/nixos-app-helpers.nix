{ lib, config, ... }:
let
  # Flatten the import tree under `flake.nixosModules.apps` into a simple
  # attribute set of name → module. This keeps roles fast and avoids probing the
  # module system on every lookup.
  flattenApps =
    module:
    if builtins.isAttrs module then
      let
        direct = lib.filterAttrs (
          name: _:
          !(lib.elem name [
            "_file"
            "imports"
          ])
        ) module;
        imported = module.imports or [ ];
        merge = acc: value: acc // flattenApps value;
      in
      lib.foldl' merge direct (if builtins.isList imported then imported else [ imported ])
    else
      { };

  availableApps =
    if lib.hasAttrByPath [ "apps" ] config.flake.nixosModules then
      flattenApps config.flake.nixosModules.apps
    else
      { };

  appKeys = lib.attrNames availableApps;

  helpers = rec {
    hasApp = name: builtins.hasAttr name availableApps;

    getApp =
      name:
      if hasApp name then
        builtins.getAttr name availableApps
      else
        let
          previewList = lib.take 20 appKeys;
          preview = lib.concatStringsSep ", " previewList;
          ellipsis = if lib.length appKeys > 20 then ", …" else "";
          suggestion = if appKeys == [ ] then "" else " Known keys (partial): ${preview}${ellipsis}";
        in
        throw ("Unknown NixOS app '" + name + "'" + suggestion);

    getApps = names: map getApp names;

    getAppOr = name: default: if hasApp name then getApp name else default;
  };
in
{
  _module.args.nixosAppHelpers = helpers;

  flake.lib.nixos = helpers;
}
