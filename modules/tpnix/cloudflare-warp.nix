/*
  Per-host Cloudflare WARP (Zero Trust) enrollment for tpnix.

  Enables the programs.cloudflare-warp.extended wrapper in Full mode
  ("Gateway with WARP"). Credentials come from secrets/cloudflare-warp.yaml
  (sops); see docs/cloudflare/warp/deployment.md for the dashboard prerequisites.

  Gated on tpnix's sopsRuntimeReady flag (modules/tpnix/policy.nix), matching the
  other tpnix sops consumers (duplicati.nix, printing.nix, fonts.nix). tpnix has no
  runtime SOPS decryption key yet, so with the flag false the wrapper stays off;
  otherwise committing secrets/cloudflare-warp.yaml would make enrolling declare
  sops.secrets."cloudflare-warp/*" and the cloudflare-warp-mdm template, and
  sops-install-secrets/activation would fail on the un-decryptable payload instead of
  the intended un-enrolled fallback. Flip the flag to true once tpnix can decrypt.

  Note: the Zero Trust team name (organization) is identifying, and this repository
  is public, so it lives in secrets/cloudflare-warp.yaml (sops) and is rendered into
  mdm.xml through a placeholder; see docs/cloudflare/warp/reference.md.
*/
{ config, ... }:
let
  inherit (config.flake.lib.nixos.hosts.tpnix) sopsRuntimeReady;
in
{
  configurations.nixos.tpnix.module = {
    programs.cloudflare-warp.extended = {
      enable = sopsRuntimeReady;
      serviceMode = "warp";
      autoConnect = 0;
      switchLocked = false;
      connectOnBoot = true;
    };
  };
}
