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

        # Workaround for upstream home-manager bug: the obsidian activation script
        # uses `install -m644` without `-D`, which fails when ~/.config/obsidian/
        # doesn't exist. This ensures the directory exists before that script runs.
        # TODO: Remove when https://github.com/nix-community/home-manager/issues/XXXX is fixed
        home.activation.ensureObsidianConfigDir = lib.hm.dag.entryBefore [ "obsidian" ] ''
          mkdir -p "$HOME/.config/obsidian"
        '';
      };
    };
}
