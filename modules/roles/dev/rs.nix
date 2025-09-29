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
      throw ("Unknown NixOS app '" + name + "' (role dev rs)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  rustModule =
    if lib.hasAttrByPath [ "lang" "rust" ] config.flake.nixosModules then
      lib.getAttrFromPath [ "lang" "rust" ] config.flake.nixosModules
    else
      throw "flake.nixosModules.lang.rust missing while constructing role.dev.rs";

  rustApps = [
    "rust-analyzer"
    "rustfmt"
    "rust-clippy"
  ];
  rustImports = [ rustModule ] ++ getApps rustApps;
in
{
  flake.nixosModules.roles.dev.rs.imports = rustImports;
}
