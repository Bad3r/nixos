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
  flake.nixosModules.apps.atuin =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.atuin ];
    };
}
