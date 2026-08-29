_: {
  configurations.nixos.songbird.module = {
    # No Name= on any of these: the kernel's own eth0/eth1/wlan0 stand under
    # net.ifnames=0, and systemd.link(5) calls a pin into those pools a race.
    # The files exist only to displace 99-default.link, whose
    # AlternativeNamesPolicy carries a "mac" token deriving an
    # enx/wlx<permanent-mac> altname from the factory address, which is the
    # value NetworkManager's "stable" policy exists to stop presenting.
    # net.ifnames=0 gates the rename only, not altname generation. NamePolicy is
    # safe to restore here precisely because there is no Name= for it to
    # override. Paths are the ID_PATH values read off the installed machine.
    systemd.network.links =
      let
        altnamesOnly = path: {
          matchConfig.Path = path;
          linkConfig = {
            NamePolicy = "keep kernel database onboard slot path";
            AlternativeNamesPolicy = "database onboard slot path";
          };
        };
      in
      {
        # Realtek RTL8126 5 GbE (r8169), the wired uplink.
        "10-realtek-5gbe" = altnamesOnly "pci-0000:84:00.0";
        # Intel I226-V 2.5 GbE (igc), second onboard port.
        "10-intel-2p5gbe" = altnamesOnly "pci-0000:85:00.0";
        # Intel BE200 Wi-Fi 7 (iwlwifi). Never carried a .link before this, so
        # it presented wlx<permanent-mac> on the stock install.
        "10-intel-be200" = altnamesOnly "pci-0000:86:00.0";
      };
  };
}
