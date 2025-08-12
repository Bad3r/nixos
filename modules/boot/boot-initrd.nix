{ lib, ... }:
{
  flake.modules.nixos.base.boot.initrd.systemd.enable = lib.mkDefault true;
}
