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
    # No service here serves DNS or DHCP to the network, so naming an interface
    # would open inbound UDP 53/67 and TCP 53 with no listener behind them.
    # Restore it only alongside a real listener, and pin that device first per
    # docs/networking/README.md: eth0 falls onto the built-in NIC whenever the
    # USB adapter is detached at boot. Pin by adding Name= to the adapter's
    # existing entry in networking.nix and dropping that entry's NamePolicy=,
    # not by authoring a second .link: udev reads only the first matching file.
    # firewall.nix warns on an unpinned kernel name and the warning clears once
    # a pin backs the entry, but it cannot tell a right kernel name from a wrong
    # one, so the pin is still the guarantee.
    firewallDnsInterfaces = [ ];
    firewallExtraTcpPortRanges = [
      {
        from = 8000;
        to = 8999;
      }
    ];
  };
}
