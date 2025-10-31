/*
  Package: atuin
  Description: Encrypted, synchronized shell history manager with powerful search.
  Homepage: https://atuin.sh/
  Documentation: https://docs.atuin.sh/
  Repository: https://github.com/atuinsh/atuin

  Summary:
    * Syncs shell history across devices using end-to-end encrypted storage and optional self-hosted servers.
    * Provides fuzzy command search, tagging, and import tooling to analyze or migrate existing history.

  Options:
    -f: Force `atuin sync -f` to perform a full history reconciliation when incremental sync misses entries.
    -i: Launch the interactive TUI with `atuin search -i` for fuzzy history filtering.
    -u <name>: Provide the username when running `atuin register -u` or `atuin login -u` on new machines.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.atuin.extended;
  AtuinModule = {
    options.programs.atuin.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable atuin.";
      };

      package = lib.mkPackageOption pkgs "atuin" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.atuin = AtuinModule;
}
