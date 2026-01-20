/*
  Package: vim
  Description: Highly configurable text editor.
  Homepage: https://www.vim.org/
*/

_: {
  flake.homeManagerModules.apps.vim =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "vim" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.vim = {
          enable = true;
          # Package installed by NixOS module (not overridable here)
        };
      };
    };
}
