/*
  Per-host Cloudflare WARP (Zero Trust) enrollment for system76.

  Enables the programs.cloudflare-warp.extended wrapper in Full mode
  ("Gateway with WARP"). Credentials come from secrets/cloudflare-warp.yaml
  (sops); see docs/cloudflare/warp/deployment.md for the dashboard prerequisites.

  Note: organization (the Zero Trust team name) is not a credential but is
  identifying, and this repository is public. To keep it out of git, move it into
  the sops secret and render it through an mdm placeholder; see
  docs/cloudflare/warp/reference.md.
*/
_: {
  configurations.nixos.system76.module = {
    programs.cloudflare-warp.extended = {
      enable = true;
      # null keeps warp-svc un-enrolled (the documented sentinel). Set the real
      # Zero Trust team name to turn on managed enrollment; a placeholder or any
      # non-team-name string now fails at eval (strMatching in the wrapper).
      organization = null;
      serviceMode = "warp";
      autoConnect = 0;
      switchLocked = false;
      connectOnBoot = true;
    };
  };
}
