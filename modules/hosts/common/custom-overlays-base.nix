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
  body = {
    imports = lib.attrValues (config.flake.customOverlays or { });
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
