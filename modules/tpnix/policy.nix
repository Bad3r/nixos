_: {
  flake.lib.nixos.hosts.tpnix = {
    # Readiness gates read by modules/hosts/common/*.
    sopsRuntimeReady = true;
    r2RuntimeReady = true;

    # Per-host values consumed by modules/hosts/common/*.
    extraHomeApps = [ "libreoffice" ];
    firewallDnsInterfaces = [ "wlp0s20f3" ];
  };
}
