/*
  System76 NH Integration

  NH is host workflow infrastructure (deployment + cleanup), not a generic
  package-only app toggle. This module wires native NixOS and Home Manager
  `programs.nh` options with owner-derived paths.
*/
{ lib, metaOwner, ... }:
{
  configurations.nixos.system76.module =
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

      home-manager.sharedModules = lib.mkAfter [
        (
          { osConfig, lib, ... }:
          let
            defaultFlake = "${osConfig.users.users.${metaOwner.username}.home}/nixos";
            osFlake = lib.attrByPath [ "programs" "nh" "flake" ] defaultFlake osConfig;
          in
          {
            programs.nh = {
              enable = lib.mkDefault true;
              flake = lib.mkDefault osFlake;
              clean.enable = lib.mkDefault false;
            };
          }
        )
      ];
    };
}
