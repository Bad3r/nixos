/*
  Per-host Cloudflare WARP (Zero Trust) enrollment for tpnix.

  Enables the programs.cloudflare-warp.extended wrapper in tunnel-only mode
  ("Secure Web Gateway without DNS filtering"). Credentials come from
  secrets/cloudflare-warp.yaml (sops); see docs/cloudflare/warp/deployment.md
  for the dashboard prerequisites.

  Tunnel-only mode preserves tpnix's NetworkManager dnsmasq private-host
  mappings while WARP supplies the tunnel, HTTP filtering, network policies,
  and posture checks. It intentionally does not use Gateway DNS.

  Gated on tpnix's sopsRuntimeReady flag (modules/tpnix/policy.nix). The flag is
  true, so this host installs warp-cli and starts nothing until
  secrets/cloudflare-warp.yaml is committed, then enrolls non-interactively. The
  gate is a kill switch: if tpnix ever loses its runtime decryption key, flipping
  the flag back to false drops the WARP stack with it, removes any previously
  rendered runtime mdm.xml on the next activation, and keeps the
  sops.secrets."cloudflare-warp/*" declarations and the cloudflare-warp-mdm
  template from failing activation on an un-decryptable payload.

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
      serviceMode = "tunnelonly";
      autoConnect = 0;
      switchLocked = false;
      connectOnBoot = true;
    };
  };
}
