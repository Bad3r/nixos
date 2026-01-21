/*
  Package: fzf
  Description: General-purpose command-line fuzzy finder for interactive filtering.
  Homepage: https://junegunn.github.io/fzf/
  Documentation: https://github.com/junegunn/fzf#usage
  Repository: https://github.com/junegunn/fzf

  Summary:
    * Offers blazing fast fuzzy search with ANSI color, multi-select, preview, and key binding integrations.
    * Provides shell widgets so Ctrl-T, Ctrl-R, and custom bindings open interactive pickers.

  Notes:
    * This module provides the enable flag for the Home Manager fzf module.
    * Package installation is handled by the Home Manager module, not this NixOS module.
*/
_:
let
  FzfModule =
    { lib, pkgs, ... }:
    {
      options.programs.fzf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable fzf.";
        };

        package = lib.mkPackageOption pkgs "fzf" { };
      };
    };
in
{
  flake.nixosModules.apps.fzf = FzfModule;
}
