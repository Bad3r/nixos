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
_:
let
  BashCompletionModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."bash-completion".extended;
    in
    {
      options.programs.bash-completion.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable bash-completion.";
        };

        package = lib.mkPackageOption pkgs "bash-completion" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.bash-completion = BashCompletionModule;
}
