{ config, ... }:
let
  helpers =
    config._module.args.nixosAppHelpers
      or (throw "nixosAppHelpers not available - ensure meta/nixos-app-helpers.nix is imported");
  inherit (helpers) getApps;

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
    "xh"
  ];
in
{
  configurations.nixos.system76.module.imports = getApps cloudflareAppNames;
}
