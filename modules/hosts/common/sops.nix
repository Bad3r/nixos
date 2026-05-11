{ config, lib, ... }:
let
  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;
  body = _: {
    config = {
      sops = {
        age = {
          keyFile = lib.mkForce "/var/lib/sops-nix/key.txt";
          sshKeyPaths = lib.mkForce [ ];
        };
        gnupg.sshKeyPaths = lib.mkForce [ ];
      };
    };
  };
in
{
  configurations.nixos.system76.module = lib.mkIf s76Share body;
  configurations.nixos.tpnix.module = lib.mkIf tpShare body;
}
