_: {
  configurations.nixos.songbird.module = {
    # Under net.ifnames=0 the two onboard NICs share the eth0/eth1 pool by
    # enumeration order, so neither kernel name is device-bound, and
    # NetworkManager's "stable" MAC policy hashes the interface name, so a
    # swap would re-key both addresses. Pin each NIC by PCI path to a name
    # outside the kernel's eth* namespace instead.
    # Each pin is the only .link udev applies to its device, so it restores the
    # alternative names 99-default.link would otherwise supply. The "mac" token
    # is dropped: that one derives an enx<permanent-mac> altname from the
    # factory address, which is the value the "stable" policy exists to stop
    # presenting. The address itself stays NetworkManager's.
    systemd.network.links = {
      # Realtek RTL8126 5 GbE (r8169), the wired uplink.
      "10-lan0" = {
        matchConfig.Path = "pci-0000:84:00.0";
        linkConfig = {
          Name = "lan0";
          AlternativeNamesPolicy = "database onboard slot path";
        };
      };
      # Intel I226-V 2.5 GbE (igc), second onboard port.
      "10-lan1" = {
        matchConfig.Path = "pci-0000:85:00.0";
        linkConfig = {
          Name = "lan1";
          AlternativeNamesPolicy = "database onboard slot path";
        };
      };
    };
  };
}
