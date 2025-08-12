# Priority: Default value that can be overridden

{ lib, ... }:
{
  flake.modules.nixos.base.boot.initrd.systemd.enable = lib.mkDefault true;
}
