_: {
  configurations.nixos.songbird.module.workloads.networks.default = {
    egress = "warp";
    isolatePeers = true;
    libvirt = {
      enable = true;
      uuid = "3f2781e9-4ec0-4023-9e00-82d7c6eee665";
      dhcp = {
        start = 100;
        end = 254;
      };
    };
  };
}
