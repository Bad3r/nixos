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
    sk --ansi: Preserve ANSI colors in the query interface.
    sk --preview <command>: Show a preview pane with dynamic content for the highlighted entry.
    sk --bind <key>:<action>: Customize key bindings and interactive actions.
    sk --cmd <command>: Pipe output from a shell command into skim lazily.
    sk-tmux: Run the fuzzy finder inside a tmux popup with helper defaults.

  Example Usage:
    * `sk --ansi < <(git status --short)` — Fuzzily select files from Git status with color-preserving output.
    * `sk --preview 'bat --style=numbers --color=always {}'` — Display syntax-highlighted previews while filtering.
    * `find . -type f | sk --bind 'ctrl-o:execute(nvim {})'` — Open selected files in Neovim directly from the picker.
*/

{
  flake.homeManagerModules.apps.skim =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.skim ];
    };
}
