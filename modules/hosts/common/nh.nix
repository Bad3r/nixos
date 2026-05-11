/*
  NH Integration (shared hosts)

  NH is host workflow infrastructure (deployment + cleanup), not a generic
  package-only app toggle. This module wires native NixOS and Home Manager
  `programs.nh` options with owner-derived paths.
*/
{
  config,
  lib,
  metaOwner,
  ...
}:
let
  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;
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
in
{
  configurations.nixos.system76.module = lib.mkIf s76Share body;
  configurations.nixos.tpnix.module = lib.mkIf tpShare body;
}
