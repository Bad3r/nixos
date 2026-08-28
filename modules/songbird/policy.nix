_: {
  flake.lib.nixos.hosts.songbird = {
    # Primary fleet endpoint handoff (`primary = true` plus `tailnetIp`) is
    # pending: the tailnet address only exists once this host has joined, and
    # a primary without an address would leave the tailscale SSH alias on
    # every other host with no HostName. Move both keys here from
    # modules/system76/policy.nix as soon as `tailscale ip -4` reports it.

    # Shared readiness gate read by modules/hosts/common/*. Flip after the
    # canonical age identity is installed at /var/lib/sops-nix/key.txt and
    # ~/.config/sops/age/keys.txt (docs/sops/README.md, Host Preparation).
    sopsRuntimeReady = false;

    # Host runtime gate read by modules/songbird/r2-runtime.nix.
    r2RuntimeReady = false;

    # Per-host values consumed by modules/hosts/common/*.
    duplicatiStateDirReadable = true;
    extraHomeApps = [
      "awscli2"
      "pentesting-devshell"
    ];
    # No service here serves DNS or DHCP to the network, so naming an interface
    # would open inbound UDP 53/67 and TCP 53 with no listener behind them.
    # Restore it only alongside a real listener, and use the pinned lan0/lan1
    # from modules/songbird/networking.nix rather than eth0/eth1: the two
    # onboard NICs share the kernel's eth* pool by enumeration order.
    firewallDnsInterfaces = [ ];
    firewallExtraTcpPortRanges = [
      {
        from = 8000;
        to = 8999;
      }
    ];
  };
}
