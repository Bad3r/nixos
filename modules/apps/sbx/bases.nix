# sbx bases build on demand (`sbx base build <flavour>`) from legacyPackages,
# which no flake check evaluates and no host closure references.
{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      legacyPackages.workloads.sbx-nixos =
        (inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ ./_base-nixos.nix ];
        }).config.system.build.images.qemu-efi;
    };
}
