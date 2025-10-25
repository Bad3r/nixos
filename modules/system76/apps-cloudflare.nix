{ config, lib, ... }:
let
  appsDir = ../apps;
  helpers = config._module.args.nixosAppHelpers or { };
  fallbackGetApp =
    name:
    let
      filePath = appsDir + "/${name}.nix";
    in
    if builtins.pathExists filePath then
      let
        exported = import filePath;
        module = lib.attrByPath [
          "flake"
          "nixosModules"
          "apps"
          name
        ] null exported;
      in
      if module != null then
        module
      else
        throw ("NixOS app '" + name + "' missing expected attrpath in " + toString filePath)
    else
      throw ("NixOS app module file not found: " + toString filePath);
  getApp = helpers.getApp or fallbackGetApp;
  getApps = helpers.getApps or (names: map getApp names);

  cloudflareAppNames = [
    "wrangler"
    "flarectl"
    "terraform"
    "cf-terraforming"
    "cloudflared"
    "cloudflare-warp"
    "wgcf"
    "s5cmd"
    "minio-client"
    "worker-build"
    "jq"
    "xh"
  ];
in
{
  configurations.nixos.system76.module.imports = getApps cloudflareAppNames;
}
