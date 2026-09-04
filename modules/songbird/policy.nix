_: {
  flake.lib.nixos.hosts.songbird = {
    # Primary fleet endpoint handoff (`primary = true` plus `tailnetIp`) is
    # pending: the tailnet address only exists once this host has joined, and
    # a primary without an address would leave the tailscale SSH alias on
    # every other host with no HostName. Move both keys here from
    # modules/system76/policy.nix as soon as `tailscale ip -4` reports it.

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
    extraHomeApps = [
      "awscli2"
      "pentesting-devshell"
    ];
    # No service here serves DNS or DHCP to the network, so naming an interface
    # would open inbound UDP 53/67 and TCP 53 with no listener behind them.
    # Restore it only alongside a real listener, and pin that device first per
    # docs/networking/README.md: eth0/eth1 track enumeration order across the
    # two onboard NICs. Pin by adding Name= to the NIC's existing entry in
    # networking.nix and dropping that entry's NamePolicy=, not by authoring a
    # second .link: udev reads only the first matching file. firewall.nix warns
    # on an unpinned kernel name and the warning clears once a pin backs the
    # entry, but it cannot tell a right kernel name from a wrong one, so the pin
    # is still the guarantee.
    firewallDnsInterfaces = [ ];
    firewallLocalTcpPortRanges = [
      # Fleet convention for local dev servers, as on system76 and tpnix.
      {
        from = 8000;
        to = 8999;
      }
      # qBittorrent's incoming-peer listener (Session\Port); LAN peers only,
      # the UDP side of the same port stays closed.
      {
        from = 55844;
        to = 55844;
      }
    ];
  };
}
