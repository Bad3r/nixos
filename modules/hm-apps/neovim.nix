/*
  Package: neovim
  Description: Vim-fork focused on extensibility and usability.
  Homepage: https://neovim.io/
*/

_: {
  flake.homeManagerModules.apps.neovim =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "neovim" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.neovim = {
          enable = true;
          # Package installed by NixOS module (not overridable here)
        };
      };
    };
}
