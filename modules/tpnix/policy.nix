_: {
  flake.lib.nixos.hosts.tpnix = {
    # Shared readiness gate read by modules/hosts/common/*.
    sopsRuntimeReady = true;

    # Host runtime gate read by modules/tpnix/r2-runtime.nix.
    r2RuntimeReady = true;

    # Per-host values consumed by modules/hosts/common/*.
    extraHomeApps = [ "libreoffice" ];
    # No service here serves DNS or DHCP to the network. The only dnsmasq is the
    # caching resolver NetworkManager spawns for dns = "dnsmasq" in
    # modules/hosts/common/private-dns-hosts.nix, and NM gives it
    # --listen-address=127.0.0.1 and ::1 with no dhcp-range, so nothing binds
    # UDP 67 or binds 53 off loopback. Naming an interface here would open
    # inbound 53/67 on Wi-Fi, untrusted networks included, with no listener.
    # Restore it only alongside a real listener, and use the pinned wifi0 rather
    # than wlan0.
    firewallDnsInterfaces = [ ];

    # secrets/tpnix.yaml keys served as dnsmasq addn-hosts files by
    # modules/hosts/common/private-dns-hosts.nix.
    privateDnsHostsSecretKeys = [ "signalx_hosts" ];
  };
}
