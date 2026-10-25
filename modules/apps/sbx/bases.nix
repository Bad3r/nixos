# sbx bases build on demand (`sbx base build <flavour>`) as workloads.artifacts
# entries (modules/workloads/artifacts.nix), which no host closure references;
# the sbx-vsock and sbx-gui checks boot `nixos` and `nixos-gui`.
{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    let
      base =
        modules:
        (inputs.nixpkgs.lib.nixosSystem {
          inherit system modules;
        }).config.system.build.images.qemu-efi;
    in
    {
      workloads.artifacts = {
        sbx-nixos = base [ ./_base-nixos.nix ];
        sbx-nixos-gui = base [
          ./_base-nixos.nix
          ./_base-nixos-gui.nix
        ];
      };
    };
}
