{ lib, ... }:
let
  # Direct import bypasses config evaluation order issues
  owner = import ../../lib/meta-owner-profile.nix;
in
{
  configurations.nixos.system76.module = {
    users.users.${owner.username}.extraGroups = lib.mkAfter [ "input" ];
  };
}
