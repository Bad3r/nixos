{ config, ... }:
let
  inherit (config.flake.lib) customPackagesOverlay;
in
{
  configurations.nixos.system76.module = {
    nixpkgs.overlays = [
      customPackagesOverlay
      (_final: prev: {
        # system76-power 1.2.8 aborts profile application when any SCSI host
        # lacks link_power_management_policy (USB-attached SCSI, virtio-scsi,
        # card readers). The daemon then keeps reporting the previous profile
        # even though CPU/pstate settings were applied. Upstream bug:
        # https://github.com/pop-os/system76-power/issues/377
        system76-power = prev.system76-power.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ../../packages/system76-power/skip-non-alpm-scsi-hosts.patch
          ];
        });
      })
    ];
  };
}
