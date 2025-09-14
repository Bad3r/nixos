{ lib, config, ... }:
{
  # Provide NixOS app composition helpers under flake.lib.nixos
  flake.lib.nixos = rec {
    hasApp = name: lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules;

    getApp =
      name:
      if hasApp name then
        lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
      else
        throw "Unknown NixOS app '${name}'";

    getApps = names: map getApp (builtins.filter hasApp names);

    getAppOr =
      name: default:
      if hasApp name then lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules else default;
  };
}
