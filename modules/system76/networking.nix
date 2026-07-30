{
  configurations.nixos.system76.module = {
    # The USB ethernet adapter carries the DNS/DHCP firewall opening declared in
    # policy.nix. Under net.ifnames=0 a bare eth0 would land on the built-in NIC
    # on any boot without the adapter attached, so pin the adapter to a name
    # outside the kernel's eth* namespace: matching on its USB path keeps a MAC
    # out of the repository, and no device is named lan0 when the adapter is
    # detached or moved to another port, which leaves the opening inert.
    systemd.network.links."10-lan0" = {
      matchConfig.Path = "pci-0000:00:14.0-usb-0:1.4:1.0";
      linkConfig.Name = "lan0";
    };
  };
}
