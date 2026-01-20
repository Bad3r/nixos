/*
  Package: obsidian
  Description: Knowledge base and note-taking app using Markdown files.
  Homepage: https://obsidian.md/
*/

_: {
  flake.homeManagerModules.apps.obsidian =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "obsidian" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.obsidian = {
          enable = true;
          # Package installed by NixOS module (not overridable here)
        };
      };
    };
}
