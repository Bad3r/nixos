_: {
  flake.lib.nixos.hosts.system76 = {
    # Primary fleet endpoint: registry consumers (ssh-hosts, tailscale)
    # point their default aliases at this machine. Hand off by moving
    # these two keys to the successor host's policy.nix.
    primary = true;
    tailnetIp = "100.64.1.5";

    # Shared readiness gate read by modules/hosts/common/*.
    sopsRuntimeReady = true;

    # Host runtime gate read by modules/system76/r2-runtime.nix.
    r2RuntimeReady = true;

    # Per-host values consumed by modules/hosts/common/*.
    duplicatiStateDirReadable = true;
    lenovoMonitorAttached = true;
    extraHomeApps = [
      "awscli2"
      "pentesting-devshell"
    ];
    # USB ethernet adapter, formerly enp0s20f0u1u4. It registers ahead of the
    # built-in enp4s0 (eth1), so it takes eth0 under net.ifnames=0.
    firewallDnsInterfaces = [ "eth0" ];
    firewallExtraTcpPortRanges = [
      {
        from = 8000;
        to = 8999;
      }
    ];
  };
}
