/*
  Per-host Cloudflare WARP (Zero Trust) enrollment for system76.

  Enables the programs.cloudflare-warp.extended wrapper in Full mode
  ("Gateway with WARP"). Credentials come from secrets/cloudflare-warp.yaml
  (sops); see docs/cloudflare/warp/deployment.md for the dashboard prerequisites.

  Note: the Zero Trust team name (organization) is identifying, and this repository
  is public, so it lives in secrets/cloudflare-warp.yaml (sops) and is rendered into
  mdm.xml through a placeholder; see docs/cloudflare/warp/reference.md.
*/
_: {
  configurations.nixos.system76.module = {
    programs.cloudflare-warp.extended = {
      enable = true;
      serviceMode = "warp";
      autoConnect = 0;
      switchLocked = false;
      connectOnBoot = true;
    };
  };
}
