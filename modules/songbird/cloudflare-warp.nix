/*
  Per-host Cloudflare WARP (Zero Trust) enrollment for songbird.

  Enables the programs.cloudflare-warp.extended wrapper in Full mode
  ("Gateway with WARP"). Credentials come from secrets/cloudflare-warp.yaml
  (sops); see docs/cloudflare/warp/deployment.md for the dashboard prerequisites.

  Full mode makes WARP the system resolver. songbird runs no local resolver on
  127.0.0.1:53, so Gateway DNS filtering does not collide the way it would on
  tpnix, whose NetworkManager dnsmasq keeps that host on tunnel-only mode.

  Gated on songbird's sopsRuntimeReady flag (modules/songbird/policy.nix) like
  the host's other secret-backed services. The flag is true, so this host
  installs warp-cli and starts nothing until secrets/cloudflare-warp.yaml is
  committed, then enrolls non-interactively. Flipping the flag back to false
  drops the WARP stack, removes any previously rendered runtime mdm.xml on the
  next activation, and keeps the sops.secrets."cloudflare-warp/*" declarations
  from failing activation on an un-decryptable payload.

  Note: the Zero Trust team name (organization) is identifying, and this repository
  is public, so it lives in secrets/cloudflare-warp.yaml (sops) and is rendered into
  mdm.xml through a placeholder; see docs/cloudflare/warp/reference.md.
*/
{ config, ... }:
let
  inherit (config.flake.lib.nixos.hosts.songbird) sopsRuntimeReady;
in
{
  configurations.nixos.songbird.module = {
    programs.cloudflare-warp.extended = {
      enable = sopsRuntimeReady;
      serviceMode = "warp";
      autoConnect = 0;
      switchLocked = false;
      connectOnBoot = true;
    };
  };
}
