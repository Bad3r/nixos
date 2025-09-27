/*
  Package: zsh-completions
  Description: Additional completion definitions extending stock Zsh functionality.
  Homepage: https://github.com/zsh-users/zsh-completions
  Documentation: https://github.com/zsh-users/zsh-completions#readme
  Repository: https://github.com/zsh-users/zsh-completions

  Summary:
    * Provides community-maintained completion scripts for hundreds of CLI tools beyond the default set.
    * Complements Oh My Zsh and vanilla Zsh setups with context-aware command flags and arguments.

  Options:
    -U: Use `autoload -U compinit` to load completion functions without creating aliases.
    -d: Pass to `compinit -d ~/.cache/zcompdump` to control the dumpfile location.
    -D: Use `compinit -D` to defer expensive completion initialization during startup.
*/

{
  flake.nixosModules.apps."zsh-completions" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."zsh-completions" ];
    };
}
