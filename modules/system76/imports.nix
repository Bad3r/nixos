{
  config,
  lib,
  inputs,
  ...
}:
let
  nm = config.flake.nixosModules;
in
{
  configurations.nixos.system76.module = {
    imports = [
      inputs.nixos-hardware.nixosModules.system76
      nm.workstation
      nm.nvidia-gpu
      nm.system76-support
      nm."role-dev"
      nm."role-media"
      nm."role-net"
    ]
    ++ lib.optional (lib.hasAttr "ssh" nm) nm.ssh;
  };
}
