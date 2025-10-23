{ config, lib, ... }:
let
  owner = config.flake.lib.meta.owner.username;
in
{
  configurations.nixos.system76.module = {
    users.users.${owner}.extraGroups = lib.mkAfter [ "input" ];
  };
}
