# sbx bases build on demand (`sbx base build <flavour>`) as workloads.artifacts
# entries (modules/workloads/artifacts.nix), which no host closure references;
# the sbx-vsock check boots `nixos`.
{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      workloads.artifacts.sbx-nixos =
        (inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ ./_base-nixos.nix ];
        }).config.system.build.images.qemu-efi;
    };
}
