{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role dev cloudflare SDK)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  languageSdks = {
    go = {
      baseModules = [ config.flake.nixosModules.lang.go ];
      apps = [ "cloudflare-go-sdk" ];
    };
    python = {
      baseModules = [ config.flake.nixosModules.lang.python ];
      apps = [ "cloudflare-python-sdk" ];
    };
    rust = {
      baseModules = [ config.flake.nixosModules.lang.rust ];
      apps = [
        "cloudflare-rs-sdk"
        "workers-rs-sdk"
      ];
    };
  };

  buildRole =
    language:
    { baseModules, apps }:
    let
      sdkImports = baseModules ++ getApps apps;
      rolePath = [
        "flake"
        "nixosModules"
        "roles"
        "dev"
        language
        "sdk"
        "cloudflare"
        "imports"
      ];
      aliasPath = [
        "flake"
        "nixosModules"
        "dev"
        language
        "sdk"
        "cloudflare"
        "imports"
      ];
    in
    (lib.setAttrByPath rolePath sdkImports) // (lib.setAttrByPath aliasPath sdkImports);

in
lib.mkMerge (lib.mapAttrsToList buildRole languageSdks)
