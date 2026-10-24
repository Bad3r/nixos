{
  config,
  lib,
  secretsRoot,
  ...
}:
let
  policy = config.flake.lib.nixos.hosts.songbird;
  inherit (policy) win11;
  inherit (config.flake.lib.nixos) sriSha256ToHex;
  songbird = config.flake.nixosConfigurations.songbird;
  nixosDevImage = config.flake.nixosConfigurations.nixos-dev.config.system.build.images.qemu-efi;
  secretFile = secretsRoot + "/workloads.yaml";
  # Both halves, as every other secret consumer here gates (services.nix).
  win11Ready = policy.sopsRuntimeReady && builtins.pathExists secretFile;
in
{
  perSystem.workloads.artifacts = {
    virtio-win = songbird.pkgs.virtio-win.src;
  }
  // lib.optionalAttrs win11Ready {
    win11-seed = songbird.config.workloads.guests.win11.windows.seedIso;
  };

  configurations.nixos.songbird.module =
    { metaOwner, pkgs, ... }:
    {
      imports =
        lib.optionals win11Ready [
          {
            sops.secrets."workloads/win11/password" = {
              sopsFile = secretFile;
              format = "yaml";
              key = "win11_password";
              owner = "root";
              group = "root";
              mode = "0400";
            };

            workloads.media = {
              win11-iso = {
                source = win11.installIso;
                sha256 = win11.installIsoSha256;
              };
              virtio-win = {
                source = win11.virtioWinIso;
                sha256 = sriSha256ToHex pkgs.virtio-win.src.outputHash;
              };
            };

            workloads.guests.win11 = {
              uuid = "7d586a9c-6290-4ece-9593-b8b0b7c26300";
              kind = "windows";
              trust = "trusted";
              inherit (win11) memory vcpus;
              cpuset = win11.cpus;
              disks.root.size = win11.disk;
              interfaces.lan = {
                network = "desktop";
                hostOffset = 11;
              };
              install.media = [
                "win11-iso"
                "virtio-win"
              ];
              windows = {
                account = {
                  name = metaOwner.username;
                  authorizedKeys = metaOwner.sshKeys;
                };
                timeZone = "Arab Standard Time";
                services.ssh.port = 22;
              };
            };
          }
        ]
        ++ lib.optionals (!win11Ready) [
          {
            warnings = [ "songbird win11 guest skipped because ${toString secretFile} is missing." ];
          }
        ];

      workloads = {
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
        };

        images.nixos-dev = {
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
    };
}
