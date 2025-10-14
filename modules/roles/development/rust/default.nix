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
      throw ("Unknown NixOS app '" + name + "' (role development.rust)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  rustModule =
    let
      path = [
        "lang"
        "rust"
      ];
    in
    if lib.hasAttrByPath path config.flake.nixosModules then
      lib.getAttrFromPath path config.flake.nixosModules
    else
      ../../../languages/lang-rust.nix;

  rustApps = [
    "rust-analyzer"
    "rustfmt"
    "rust-clippy"
    "cargo"
    "rustc"
  ];
  rustImports = [ rustModule ] ++ getApps rustApps;
in
{
  flake.nixosModules.roles.development.rust = {
    metadata = {
      canonicalAppStreamId = "Development";
      categories = [ "Development" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = rustImports;
  };
}
