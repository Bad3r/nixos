_: {
  configurations.nixos.tpnix.module = {
    # Traffic only: NetworkManager's dnsmasq keeps serving the private-host
    # mappings from modules/hosts/common/private-dns-hosts.nix, which Gateway
    # DNS in warp mode would replace. Enablement is the apps-enable override.
    programs.cloudflare-warp.extended.serviceMode = "tunnelonly";
  };
}
