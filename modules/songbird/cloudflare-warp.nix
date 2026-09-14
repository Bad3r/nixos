_: {
  configurations.nixos.songbird.module = {
    # Gateway with WARP: the WARP resolver becomes the system DNS, since
    # nothing here serves private-host mappings. warp-svc writes
    # /etc/resolv.conf itself (its resolved probe rejects systemd 261's
    # version string), so resolvectl never lists it. Enablement is the
    # apps-enable override.
    programs.cloudflare-warp.extended.serviceMode = "warp";
  };
}
