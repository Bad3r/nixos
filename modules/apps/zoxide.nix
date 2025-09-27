/*
  Package: zoxide
  Description: Fast directory jumper that learns your navigation patterns.
  Homepage: https://zoxide.dev/
  Documentation: https://zoxide.dev/guide
  Repository: https://github.com/ajeetdsouza/zoxide

  Summary:
    * Tracks frequently used directories and offers `cd`-like jumps with shell-integrated completions.
    * Supports multiple shells, weighting algorithms, and interactive `fzf`-style selection.

  Options:
    -i: Launch the interactive selector `zoxide query -i` for fuzzy-ranked directory jumps.
    --cmd <name>: Generate init scripts that bind the `z` command to a custom alias (e.g., `zoxide init --cmd cd zsh`).
    --list: Print the contents of the database with scores via `zoxide query --list`.
*/

{
  flake.nixosModules.apps.zoxide =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.zoxide ];
    };
}
