# Safe to load everywhere: each module gates on its NixOS row, own enable option, or NixOS setting.
{ config, lib, ... }:
let
  body = {
    home-manager.sharedModules = lib.mkAfter (
      lib.attrValues config.flake.homeManagerModules.apps
      ++ lib.attrValues config.flake.homeManagerModules.browsers
    );
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
