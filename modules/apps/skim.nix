/*
  Package: skim
  Description: Fuzzy finder (`sk`) written in Rust with rich preview and multi-select capabilities.
  Homepage: https://github.com/lotabout/skim
  Documentation: https://github.com/lotabout/skim#usage
  Repository: https://github.com/lotabout/skim

  Summary:
    * Provides a fast, flexible fuzzy finder for use in the terminal, supporting async sources, interactive filtering, preview windows, and keybindings similar to fzf.
    * Includes integrations for shell history, git, file search, and more via bundled scripts.

  Options:
    sk: Invoke the fuzzy finder reading from stdin.
    sk --query <text>: Start with an initial search query.
    sk --ansi --preview 'bat --style=plain --color=always {}': Enable ANSI color support and file previews.
    sk --bind 'ctrl-s:toggle-sort': Customize keybindings during interactive sessions.

  Example Usage:
    * `find . -type f | sk` -- Fuzzy-select files within the current directory.
    * `git branch | sk --ansi --query feature` -- Filter git branches with initial query text.
    * `sk --tac --expect=ctrl-y` -- Reverse the list order and capture custom key events for scripting.
*/
_:
let
  SkimModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.skim.extended;
    in
    {
      options.programs.skim.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable skim.";
        };

        package = lib.mkPackageOption pkgs "skim" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.skim = SkimModule;
}
