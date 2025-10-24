{ config, lib, ... }:
let
  getAppModule =
    name:
    let
      path = [
        "flake"
        "nixosModules"
        "apps"
        name
      ];
    in
    lib.attrByPath path (throw "Missing NixOS app '${name}' while wiring System76 Cloudflare tooling.")
      config;

  getApps = config.flake.lib.nixos.getApps or (names: map getAppModule names);

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
