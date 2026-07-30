_: {
  flake.lib.nixos.hosts.tpnix = {
    # Shared readiness gate read by modules/hosts/common/*.
    sopsRuntimeReady = true;

    # Host runtime gate read by modules/tpnix/r2-runtime.nix.
    r2RuntimeReady = true;

    # Per-host values consumed by modules/hosts/common/*.
    extraHomeApps = [ "libreoffice" ];
    # Internal Wi-Fi card, formerly wlp0s20f3, pinned to wifi0 by the .link in
    # modules/tpnix/networking.nix. A bare wlan0 would follow registration order
    # onto a USB adapter attached at boot, and this value opens UDP 53/67 and
    # TCP 53 for NetworkManager's dnsmasq.
    firewallDnsInterfaces = [ "wifi0" ];
  };
}
