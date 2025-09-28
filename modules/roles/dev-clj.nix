{
  config,
  lib,
  ...
}:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role dev clj)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  clojureModule =
    if lib.hasAttrByPath [ "lang" "clojure" ] config.flake.nixosModules then
      lib.getAttrFromPath [ "lang" "clojure" ] config.flake.nixosModules
    else
      throw "flake.nixosModules.lang.clojure missing while constructing role.dev.clj";

  clojureApps = [ "pixman" ];
  clojureImports = [ clojureModule ] ++ getApps clojureApps;
in
{
  flake.nixosModules.roles.dev.clj.imports = clojureImports;
  flake.nixosModules.roles.dev.clj.pixman = getApp "pixman";
}
