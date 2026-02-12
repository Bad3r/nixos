/*
  System76 NH Integration

  NH is host workflow infrastructure (deployment + cleanup), not a generic
  package-only app toggle. This module wires native NixOS and Home Manager
  `programs.nh` options with owner-derived paths.
*/
{ lib, metaOwner, ... }:
let
  ownerName = metaOwner.username;
  ownerHome = "/home/${ownerName}";
  ownerFlakeDir = "${ownerHome}/nixos";
in
{
  configurations.nixos.system76.module = {
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
          osFlake = lib.attrByPath [ "programs" "nh" "flake" ] ownerFlakeDir osConfig;
        in
        {
          programs.nh = {
            enable = lib.mkDefault true;
            flake = lib.mkDefault osFlake;
            osFlake = lib.mkDefault osFlake;
            homeFlake = lib.mkDefault osFlake;
            clean.enable = lib.mkDefault false;
          };
        }
      )
    ];
  };
}
