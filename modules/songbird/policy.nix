_: {
  flake.lib.nixos.hosts.songbird = {
    # Shared readiness gate read by modules/hosts/common/*. The canonical age
    # identity is installed at /var/lib/sops-nix/key.txt and
    # ~/.config/sops/age/keys.txt (docs/sops/README.md, Host Preparation).
    sopsRuntimeReady = true;

    # Host runtime gate read by modules/songbird/r2-runtime.nix.
    r2RuntimeReady = true;

    # NVIDIA-enabled hosts must declare this Boolean. The CachyOS kernel is
    # built from source on songbird and has no configured substituter, so keep
    # its kernel module local while retaining nvidia-x11 and nvidia-settings.
    cacheRoots.nvidiaKernelModules = false;

    # Per-host values consumed by modules/hosts/common/*.
    duplicatiStateDirReadable = true;
    cloudflareWarpMeshAddressReady = true;
    extraHomeApps = [
      "awscli2"
      "pentesting-devshell"
    ];
    firewallLocalTcpPortRanges = [
      # Fleet convention for local dev servers, as on tpnix.
      {
        from = 8000;
        to = 8999;
      }
    ];
  };
}
