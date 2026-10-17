/*
  NH Integration (shared hosts)

  NH is host workflow infrastructure (deployment + cleanup), not a generic
  package-only app toggle. This module wires the native NixOS `programs.nh`
  options with owner-derived paths.
*/
{
  lib,
  metaOwner,
  ...
}:
let
  body =
    { config, ... }:
    let
      ownerHome = config.users.users.${metaOwner.username}.home;
      ownerFlakeDir = "${ownerHome}/nixos";
    in
    {
      programs.nh = {
        enable = lib.mkDefault true;
        flake = lib.mkDefault ownerFlakeDir;

        clean = {
          enable = lib.mkDefault true;
          dates = lib.mkDefault "weekly";
          extraArgs = lib.mkDefault "--keep-since 14d --keep 3";
        };
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
