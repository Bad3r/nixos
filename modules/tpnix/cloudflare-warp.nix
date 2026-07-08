/*
  Per-host Cloudflare WARP (Zero Trust) enrollment for tpnix.

  Enables the programs.cloudflare-warp.extended wrapper in Full mode
  ("Gateway with WARP"). Credentials come from secrets/cloudflare-warp.yaml
  (sops); see docs/cloudflare/warp/deployment.md for the dashboard prerequisites.

  Gated on tpnix's sopsRuntimeReady flag (modules/tpnix/policy.nix), matching the
  other tpnix sops consumers (duplicati.nix, printing.nix, fonts.nix). Repo-managed
  sops decryption is enabled for tpnix (PR #305), so the flag is true and the
  wrapper behaves like system76's: un-enrolled degraded mode (build warning, no
  managed mdm.xml) until secrets/cloudflare-warp.yaml is committed, then
  non-interactive enrollment. The gate still matters as a kill switch: if tpnix
  ever loses its runtime decryption key, flipping the flag back to false drops the
  WARP stack with it, so the sops.secrets."cloudflare-warp/*" declarations and the
  cloudflare-warp-mdm template cannot fail activation on an un-decryptable payload.

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
