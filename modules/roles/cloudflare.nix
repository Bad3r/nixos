{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role cloudflare)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);
  cloudflareApps = [
    "wrangler"
    "flarectl"
    "terraform"
    "cf-terraforming"
    "cloudflared"
    "cloudflare-warp"
    "wgcf"
    "s5cmd"
    "minio-client"
    # "awscli2"
    "worker-build"
    "jq"
    "xh"
  ];
  roleImports = getApps cloudflareApps;
in
{
  flake.nixosModules.roles.cloudflare.imports = roleImports;
}
