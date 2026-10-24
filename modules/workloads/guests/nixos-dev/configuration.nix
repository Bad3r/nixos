{ config, ... }:
let
  guestBase = config.flake.nixosModules."workloads-guest-base";
in
{
  configurations.nixos.nixos-dev.module = {
    imports = [ guestBase ];

    system.stateVersion = "26.11";
  };

  perSystem.workloads.artifacts.nixos-dev =
    config.flake.nixosConfigurations.nixos-dev.config.system.build.images.qemu-efi;
}
