{ config, ... }:
let
  guestBase = config.flake.nixosModules."workloads-guest-base";
  declaration = config.flake.nixosConfigurations.songbird.config.workloads.guests.nixos-dev;
in
{
  configurations.nixos.nixos-dev.module = {
    imports = [ guestBase ];

    workloads.guest.shares = declaration.mounts;

    system.stateVersion = "26.11";
  };

  perSystem.workloads.artifacts.nixos-dev =
    config.flake.nixosConfigurations.nixos-dev.config.system.build.images.qemu-efi;
}
