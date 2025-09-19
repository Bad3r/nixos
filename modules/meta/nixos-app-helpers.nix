{ lib, config, ... }:
let
  helpers = rec {
    hasApp = name: lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules;

    getApp =
      name:
      if hasApp name then
        lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
      else
        let
          available = config.flake.nixosModules.apps or { };
          keys = lib.attrNames available;
          previewList = lib.take 20 keys;
          preview = lib.concatStringsSep ", " previewList;
          ellipsis = if lib.length keys > 20 then ", …" else "";
          suggestion = if keys == [ ] then "" else " Known keys (partial): ${preview}${ellipsis}";
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
