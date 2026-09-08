_: {
  flake.lib.nixos.hosts.songbird = {
    # Primary fleet endpoint: programs.tailscale.extended.sshHostName in
    # modules/apps/tailscale.nix defaults to the tailnetIp of whichever
    # registry host is marked primary. Hand off by moving these two keys, then
    # switch every host whose Home Manager config renders the fleet SSH alias.
    primary = true;
    tailnetIp = "100.120.100.117";

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
    # two onboard NICs. Pin by replacing the NIC's altnamesOnly entry in
    # networking.nix with an explicit linkConfig (Name= plus
    # AlternativeNamesPolicy=, no NamePolicy=), not by authoring a
    # second .link: udev reads only the first matching file. firewall.nix warns
    # on an unpinned kernel name and the warning clears once a pin backs the
    # entry, but it cannot tell a right kernel name from a wrong one, so the pin
    # is still the guarantee.
    firewallDnsInterfaces = [ ];
    firewallLocalTcpPortRanges = [
      # Fleet convention for local dev servers, as on tpnix.
      {
        from = 8000;
        to = 8999;
      }
    ];
  };
}
