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
    * `lazygit` -- Open lazygit in the current git repository
    * `lazygit -p /path/to/repo` -- Open lazygit in a specific repository
*/

_: {
  flake.homeManagerModules.apps.lazygit =
    { osConfig, lib, ... }:
    let
      cfg = lib.attrByPath [ "programs" "lazygit" "extended" ] { enable = false; } osConfig;
    in
    {
      config = lib.mkIf cfg.enable {
        # Home Manager's own `lg` drops lazygit's exit status and cds without checking the path.
        programs.zsh.siteFunctions.lg = ''
          local -x LAZYGIT_NEW_DIR_FILE="''${XDG_CACHE_HOME:-$HOME/.cache}/lazygit/newdir"
          local lazygit_status lazygit_new_dir

          mkdir -p -- "''${LAZYGIT_NEW_DIR_FILE:h}"
          ${lib.getExe cfg.package} "$@"
          lazygit_status=$?

          if [[ -f $LAZYGIT_NEW_DIR_FILE ]]; then
            lazygit_new_dir="$(<$LAZYGIT_NEW_DIR_FILE)"
            rm -f -- "$LAZYGIT_NEW_DIR_FILE"
            if [[ -n $lazygit_new_dir && -d $lazygit_new_dir ]]; then
              cd -- "$lazygit_new_dir"
            fi
          fi

          return $lazygit_status
        '';

        programs.lazygit = {
          enable = true;
          enableZshIntegration = false;
          package = null;

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
