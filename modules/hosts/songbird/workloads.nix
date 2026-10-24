{ config, ... }:
let
  nixosDevImage = config.flake.nixosConfigurations.nixos-dev.config.system.build.images.qemu-efi;
in
{
  configurations.nixos.songbird.module.workloads = {
    networks = {
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

      # sbx sandboxes on `--net egress`; none holds a reservation, so the pool spans the subnet.
      sbx = {
        egress = "warp";
        isolatePeers = true;
        libvirt = {
          enable = true;
          uuid = "ba3452f4-c558-479f-9ec4-c10cdf3f85cc";
          dhcp = {
            start = 2;
            end = 254;
          };
          autostart = true;
          sessionAttach = true;
        };
      };
    };

    # Built by `nix build .#legacyPackages.x86_64-linux.workloads.nixos-dev --out-link /var/lib/workloads/images/nixos-dev`.
    images.nixos-dev = {
      path = "/var/lib/workloads/images/nixos-dev/${nixosDevImage.passthru.filePath}";
      expected = "${nixosDevImage}/${nixosDevImage.passthru.filePath}";
    };

    guests.nixos-dev = {
      uuid = "f139f439-7d72-4b70-a25a-b9017a5fcddd";
      kind = "nixos";
      trust = "trusted";
      memory = 8192;
      vcpus = 4;
      display = "headless";
      disks.root = {
        size = 64;
        seed = "nixos-dev";
      };
      interfaces.lan = {
        network = "desktop";
        hostOffset = 10;
      };
    };

  };
}
