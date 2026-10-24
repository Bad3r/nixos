_: {
  flake.lib.nixos.hosts.songbird = {
    # Shared readiness gate read by modules/hosts/common/*. The canonical age
    # identity is installed at /var/lib/sops-nix/key.txt and
    # ~/.config/sops/age/keys.txt (docs/sops/README.md, Host Preparation).
    sopsRuntimeReady = true;

    # Host runtime gate read by modules/hosts/songbird/r2-runtime.nix.
    r2RuntimeReady = true;

    # NVIDIA-enabled hosts must declare this Boolean. The CachyOS kernel is
    # built from source on songbird and has no configured substituter, so keep
    # its kernel module local while retaining nvidia-x11 and nvidia-settings.
    cacheRoots.nvidiaKernelModules = false;

    # Runs the fleet's RustDesk ID and relay servers, read by
    # modules/apps/rustdesk/nixos.nix on every host.
    rustdeskServer = true;

    # Per-host values consumed by modules/hosts/common/*.
    duplicatiStateDirReadable = true;
    cloudflareWarpMeshAddressReady = true;
    firewallLocalTcpPortRanges = [
      # Local dev server range.
      {
        from = 8000;
        to = 8999;
      }
    ];

    # Address registry for workloads.networks (modules/workloads/networks.nix).
    workloadNetworkIds = {
      default = 0;
      desktop = 1;
    };

    # Ceilings for every sbx sandbox together (modules/apps/sbx/nixos.nix).
    sbx = {
      running = 3;
      memory = 12;
      # E-cores; the P-cores stay with the desktop.
      cpus = "8-23";
      ttl = 2;
      maxTtl = 24;
      disk = 30;
      minFree = 200;
    };
  };
}
