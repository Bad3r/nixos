{ config, lib, ... }:
let
  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;
  body = {
    nix.settings = {
      experimental-features = lib.mkDefault [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];
      auto-optimise-store = lib.mkDefault true;
      cores = lib.mkDefault 0;
    };
  };
in
{
  configurations.nixos.system76.module = lib.mkIf s76Share body;
  configurations.nixos.tpnix.module = lib.mkIf tpShare body;
}
