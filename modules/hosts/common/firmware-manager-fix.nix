{ config, lib, ... }:
let
  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;
  body = {
    nixpkgs.overlays = [
      (_final: prev: {
        firmware-manager = prev.firmware-manager.overrideAttrs (oldAttrs: {
          nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [
            prev.pkg-config
          ];
          buildInputs = (oldAttrs.buildInputs or [ ]) ++ [
            prev.xz # Provides liblzma
          ];
          # Ensure pkg-config can find liblzma
          PKG_CONFIG_PATH = "${prev.xz.dev}/lib/pkgconfig";
        });
      })
    ];
  };
in
{
  configurations.nixos.system76.module = lib.mkIf s76Share body;
  configurations.nixos.tpnix.module = lib.mkIf tpShare body;
}
