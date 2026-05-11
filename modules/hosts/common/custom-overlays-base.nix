/*
  Custom Overlays Auto-Import (shared hosts)

  Pulls every overlay registered under `flake.customOverlays.*`
  (auto-discovered from `modules/custom-overlays/`) into the host's module
  tree. Each overlay submodule gates itself on
  `programs.<name>.extended.enable`, so an overlay only contributes to
  `nixpkgs.overlays` when its matching app module is enabled.

  Adding a new overlay: drop a file in `modules/custom-overlays/<name>.nix`
  that registers `flake.customOverlays.<name>`. No edits here.
*/
{ config, lib, ... }:
let
  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;
  body = {
    imports = lib.attrValues (config.flake.customOverlays or { });
  };
in
{
  configurations.nixos.system76.module = lib.mkIf s76Share body;
  configurations.nixos.tpnix.module = lib.mkIf tpShare body;
}
