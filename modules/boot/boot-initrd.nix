# Module: boot-initrd.nix
# Purpose: Enable systemd in initrd for faster boot
# Namespace: flake.modules.nixos.base
# Priority: Default value that can be overridden

{ lib, ... }:
{
  flake.modules.nixos.base.boot.initrd.systemd.enable = lib.mkDefault true;
}
