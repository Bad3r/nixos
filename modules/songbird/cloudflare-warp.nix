_: {
  configurations.nixos.songbird.module = {
    # Gateway with WARP: the WARP resolver becomes the system DNS through
    # systemd-resolved, since nothing here serves private-host mappings.
    # Enablement is the apps-enable override.
    programs.cloudflare-warp.extended.serviceMode = "warp";
  };
}
