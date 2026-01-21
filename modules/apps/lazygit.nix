/*
  Package: lazygit
  Description: Terminal UI for git commands with keyboard shortcuts and visual interface.
  Homepage: https://github.com/jesseduffield/lazygit
  Documentation: https://github.com/jesseduffield/lazygit/blob/master/docs/Config.md
  Repository: https://github.com/jesseduffield/lazygit

  Summary:
    * Provides a simple terminal UI for common git operations with keyboard-driven navigation.
    * Supports staging, committing, branching, merging, rebasing, and viewing diffs visually.

  Notes:
    * This module provides the enable flag for the Home Manager lazygit module.
    * Package installation is handled by the Home Manager module, not this NixOS module.
*/
_:
let
  LazygitModule =
    { lib, pkgs, ... }:
    {
      options.programs.lazygit.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable lazygit.";
        };

        package = lib.mkPackageOption pkgs "lazygit" { };
      };
    };
in
{
  flake.nixosModules.apps.lazygit = LazygitModule;
}
