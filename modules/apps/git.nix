/*
  Package: git
  Description: Distributed version control system for tracking and collaborating on code.
  Homepage: https://git-scm.com/
  Documentation: https://git-scm.com/doc
  Repository: https://github.com/git/git

  Summary:
    * Provides branching, merging, history inspection, and transport protocols for source control.
    * Powers automation, CI/CD, and review workflows with extensive hooks and tooling integrations.

  Options:
    --global user.name "<name>": Configure author identity globally via `git config`.
    --stat: Show summarized diff statistics when used with `git log --stat` or `git show --stat`.
    --amend: Rewrite the previous commit when passed to `git commit --amend` for quick fixes.
*/

{
  flake.nixosModules.apps.git =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.git ];
    };
}
