{ lib, metaOwner, ... }:
{
  configurations.nixos.system76.module = {
    users.users.${metaOwner.username}.extraGroups = lib.mkAfter [ "input" ];
  };
}
