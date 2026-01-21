/*
  Package: lazygit
  Description: Terminal UI for git commands with keyboard shortcuts and visual interface.
  Homepage: https://github.com/jesseduffield/lazygit
  Documentation: https://github.com/jesseduffield/lazygit/blob/master/docs/Config.md
  Repository: https://github.com/jesseduffield/lazygit

  Summary:
    * Provides a simple terminal UI for common git operations with keyboard-driven navigation.
    * Supports staging, committing, branching, merging, rebasing, and viewing diffs visually.
    * Highly customizable with theme support and configurable keybindings.

  Features:
    * Visual staging and unstaging of files
    * Interactive rebasing
    * Branch management
    * Stash management
    * Diff viewing

  Keybindings:
    * x: Open command menu
    * <space>: Toggle staged/unstaged
    * c: Commit
    * p: Push
    * P: Pull
    * +: Next screen mode
    * ?: Show keybindings help

  Example Usage:
    * `lazygit` — Open lazygit in the current git repository
    * `lazygit -p /path/to/repo` — Open lazygit in a specific repository
*/

_: {
  flake.homeManagerModules.apps.lazygit =
    { osConfig, lib, ... }:
    let
      enabled = lib.attrByPath [ "programs" "lazygit" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf enabled {
        programs.lazygit = {
          enable = true;

          # Custom settings can be added here
          # settings = {
          #   gui = {
          #     theme = {
          #       activeBorderColor = ["#88c0d0" "bold"];
          #       inactiveBorderColor = ["#4c566a"];
          #       selectedLineBgColor = ["#3b4252"];
          #     };
          #   };
          #   git = {
          #     paging = {
          #       colorArg = "always";
          #       pager = "delta --dark --paging=never";
          #     };
          #   };
          # };
        };
      };
    };
}
