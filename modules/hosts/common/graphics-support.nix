{ config, lib, ... }:
let
  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;
  body =
    { pkgs, ... }:
    {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          mesa
          libva
          libvdpau
          libglvnd
        ];
        extraPackages32 = with pkgs.pkgsi686Linux; [
          mesa
          libva
          libvdpau
          libglvnd
        ];
      };

      environment.systemPackages = lib.mkAfter [ pkgs.libva-utils ];
    };
in
{
  configurations.nixos.system76.module = lib.mkIf s76Share body;
  configurations.nixos.tpnix.module = lib.mkIf tpShare body;
}
