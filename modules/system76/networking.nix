{
  configurations.nixos.system76.module = {
    # Under net.ifnames=0 the USB ethernet adapter and the built-in NIC share the
    # eth0/eth1 pool by enumeration order, so neither name is device-bound. Pin
    # the adapter to a name outside the kernel's eth* namespace instead, so
    # anything keyed to it follows the adapter: matching on its USB path keeps a
    # MAC out of the repository, and no device is named lan0 when the adapter is
    # detached or moved to another port, which fails closed rather than onto the
    # built-in NIC.
    # This pin is the only .link udev applies to the adapter, so it restores the
    # AlternativeNamesPolicy that 99-default.link would otherwise give it; the
    # address stays NetworkManager's.
    systemd.network.links."10-lan0" = {
      matchConfig.Path = "pci-0000:00:14.0-usb-0:1.4:1.0";
      linkConfig = {
        Name = "lan0";
        AlternativeNamesPolicy = "database onboard slot path mac";
      };
    };
  };
}
