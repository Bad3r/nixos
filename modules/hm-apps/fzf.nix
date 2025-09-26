/*
  Package: fzf
  Description: General-purpose command-line fuzzy finder for interactive filtering of lists and files.
  Homepage: https://junegunn.github.io/fzf/
  Documentation: https://github.com/junegunn/fzf#usage
  Repository: https://github.com/junegunn/fzf

  Summary:
    * Offers blazing fast fuzzy search with ANSI color, multi-select, preview, and key binding integrations across shells and editors.
    * Provides shell widgets and completion hooks so `Ctrl-T`, `Ctrl-R`, and custom bindings open interactive pickers within your shell session.

  Options:
    fzf --preview <command>: Render a preview window for the currently selected entry.
    fzf --bind <key>:<action>: Customize keyboard mappings or trigger commands mid-search.
    fzf --query <string>: Start the finder with an initial query pre-populated.
    fzf --multi: Enable selection of multiple entries prior to output.
    fzf-tmux -p [height[%]][,width[%]][,x,y]: Launch fzf in a tmux popup with specific dimensions.

  Example Usage:
    * `fzf` — Pipe in a list (for example `rg --files | fzf`) to interactively filter entries.
    * `fzf --preview 'bat --style=numbers --color=always {}'` — Show syntax-highlighted previews as you traverse files.
    * `fzf --bind 'ctrl-a:select-all' --multi` — Select many items using custom key bindings within the picker.
*/

{
  flake.homeManagerModules.apps.fzf = _: {
    programs.fzf = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
    };
  };
}
