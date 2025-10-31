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
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.zsh-completions.extended;
  ZshCompletionsModule = {
    options.programs.zsh-completions.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable zsh-completions.";
      };

      package = lib.mkPackageOption pkgs "zsh-completions" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.zsh-completions = ZshCompletionsModule;
}
