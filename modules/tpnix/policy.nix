_: {
  flake.lib.nixos.hosts.tpnix = {
    # Shared readiness gate read by modules/hosts/common/*.
    sopsRuntimeReady = true;

    # Host runtime gate read by modules/tpnix/r2-runtime.nix.
    r2RuntimeReady = true;

    # Per-host values consumed by modules/hosts/common/*.
    extraHomeApps = [ "libreoffice" ];
    firewallDnsInterfaces = [ "wlp0s20f3" ];

    # secrets/tpnix.yaml keys served as dnsmasq addn-hosts files by
    # modules/hosts/common/private-dns-hosts.nix.
    privateDnsHostsSecretKeys = [ "signalx_hosts" ];
  };
}
