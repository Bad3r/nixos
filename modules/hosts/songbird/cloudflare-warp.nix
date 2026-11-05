_: {
  configurations.nixos.songbird.module = {
    # Gateway with WARP: the WARP resolver answers every lookup through
    # systemd-resolved while the tunnel is up, since nothing here serves
    # private-host mappings. Enablement is the apps-enable override.
    programs.cloudflare-warp.extended.serviceMode = "warp";
    # songbird/routed lists the ranges the darah-nes2 tunnel carries, which
    # must enter WARP instead of staying on the local network.
    programs.cloudflare-warp.extended.routedRanges = true;
  };
}
