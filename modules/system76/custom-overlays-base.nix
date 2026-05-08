/*
  System76 Custom Overlays Auto-Import

  Pulls every overlay registered under `flake.customOverlays.*`
  (auto-discovered from `modules/custom-overlays/`) into this host's module
  tree. Each overlay submodule gates itself on
  `programs.<name>.extended.enable`, so an overlay only contributes to
  `nixpkgs.overlays` when its matching app module is enabled.

  Adding a new overlay: drop a file in `modules/custom-overlays/<name>.nix`
  that registers `flake.customOverlays.<name>`. No edits here.
*/
{ config, lib, ... }:
{
  configurations.nixos.system76.module.imports = lib.attrValues (config.flake.customOverlays or { });
}
