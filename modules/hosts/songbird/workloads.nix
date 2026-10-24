_: {
  configurations.nixos.songbird.module.workloads.host.services.dev = {
    ports = [
      {
        from = 8000;
        to = 8999;
      }
    ];
    bind = "any";
    grantable = true;
  };

  configurations.nixos.songbird.module.workloads.networks = {
    default = {
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

    # Declared trusted guests; their reservations sit below the DHCP range.
    desktop = {
      egress = "warp";
      libvirt = {
        enable = true;
        uuid = "e4fd11ec-c82a-440f-b072-8bf3c18f0127";
        dhcp = {
          start = 100;
          end = 254;
        };
      };
    };
  };
}
