/*
  Package: skim
  Description: Command-line fuzzy finder written in Rust.
  Homepage: https://github.com/skim-rs/skim
  Documentation: https://github.com/skim-rs/skim#readme
  Repository: https://github.com/skim-rs/skim

  Summary:
    * Interactive fuzzy finder (`sk`) with smart ranking, ANSI color support, preview windows, and multi-select capabilities.
    * Ships shell integrations for Bash, Zsh, Fish, as well as Vim/Neovim plugins and tmux helpers.

  Options:
    --ansi: Preserve ANSI colors in the query interface.
    --preview <command>: Show a preview pane with dynamic content for the highlighted entry.
    --bind <key>:<action>: Customize key bindings and interactive actions.
    --cmd <command>: Pipe output from a shell command into skim lazily.
    --layout=reverse: Flip the result list to appear above the query prompt.

  Example Usage:
    * `sk --ansi < <(git status --short)` -- Fuzzily select files from Git status with color-preserving output.
    * `sk --preview 'bat --style=numbers --color=always {}'` -- Display syntax-highlighted previews while filtering.
    * `find . -type f | sk --bind 'ctrl-o:execute(nvim {})'` -- Open selected files in Neovim directly from the picker.
*/

_: {
  flake.homeManagerModules.apps.skim =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "skim" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.skim = {
          enable = true;
          enableZshIntegration = true;
          enableBashIntegration = true;
        };
      };
    };
}
