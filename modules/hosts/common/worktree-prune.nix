# Biweekly-ish cleanup of stale branches and worktrees for the primary user.
# The nixos checkout is scanned explicitly so gone branches are pruned even
# when no worktree for them remains under ~/trees; hosts without that path
# get a reported, non-fatal skip.
{
  config,
  lib,
  metaOwner,
  ...
}:
let
  worktreePruneModule =
    config.flake.homeManagerModules.apps."worktree-prune"
      or (throw "Home Manager app module 'worktree-prune' not found in flake.homeManagerModules.apps");

  body = _: {
    config = {
      home-manager = {
        extraAppImports = lib.mkAfter [ "worktree-prune" ];
        sharedModules = lib.mkAfter [ worktreePruneModule ];

        users.${metaOwner.username}.programs.worktreePrune = {
          enable = true;
          repos = [ "/home/${metaOwner.username}/nixos" ];
        };
      };
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
