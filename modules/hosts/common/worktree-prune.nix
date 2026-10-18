# Biweekly-ish cleanup of stale branches and worktrees for the primary user.
# The nixos checkout is scanned explicitly so gone branches are pruned even
# when no worktree for them remains under ~/trees; hosts without that path
# get a reported, non-fatal skip.
{ metaOwner, ... }:
let
  body = _: {
    config = {
      home-manager.users.${metaOwner.username}.programs.worktreePrune = {
        enable = true;
        repos = [ "/home/${metaOwner.username}/nixos" ];
      };
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
