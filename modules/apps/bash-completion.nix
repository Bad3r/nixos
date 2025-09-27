/*
  Package: bash-completion
  Description: Programmable completion framework for the GNU Bash shell.
  Homepage: https://github.com/scop/bash-completion
  Documentation: https://github.com/scop/bash-completion#readme
  Repository: https://github.com/scop/bash-completion

  Summary:
    * Ships an extensive library of completions covering common Unix tools, languages, and package managers.
    * Exposes helper utilities so maintainers can author context-aware completions for custom commands.

  Options:
    -F <function>: Use with `complete -F` to attach a Bash completion function to a command.
    -o bashdefault: Merge custom completions with Bash defaults via `complete -o`.
    -C <command>: Delegate completion generation to an external helper command.
*/

{
  flake.nixosModules.apps."bash-completion" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."bash-completion" ];
    };
}
