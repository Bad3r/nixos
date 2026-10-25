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
      sbx = 2;
    };

    # The win11 guest (modules/hosts/songbird/workloads.nix): memory in MiB,
    # P-cores, disk in GiB.
    win11 = {
      memory = 12288;
      vcpus = 6;
      cpus = "0-7";
      disk = 128;
      # /data is a nofail LUKS mount; workloads-vm-media requires it.
      installIso = "/data/Misc/windows/en-us_windows_11_business.iso";
      installIsoSha256 = "9a9428dcf8ad48391744ac63062619e05758230fe4e9c9753515d413cfc316bb";
      # `{ source; sha256; }` of an OfficeSetup.exe that provisioning runs, or null.
      officeInstaller = null;
    };

    # Ceilings for every sbx sandbox together (modules/apps/sbx/nixos.nix).
    sbx = {
      running = 3;
      memory = 10;
      sliceMemory = 12;
      # E-cores; the P-cores stay with the desktop.
      cpus = "8-23";
      ttl = 2;
      maxTtl = 24;
      disk = 30;
      minFree = 200;
    };
  };
}
