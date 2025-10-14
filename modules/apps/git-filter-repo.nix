/*
  Package: git-filter-repo
  Description: Fast and flexible Git history rewriting tool designed to replace `git filter-branch` and BFG.
  Homepage: https://github.com/newren/git-filter-repo
  Documentation: https://github.com/newren/git-filter-repo#readme
  Repository: https://github.com/newren/git-filter-repo

  Summary:
    * Rewrites Git repositories by filtering, renaming, or removing paths, emails, and commit messages with high performance.
    * Provides Python-based extension points and built-in mappings for tasks like stripping large files or converting authors.

  Options:
    --path <path>: Retain only history touching the specified path.
    --invert-paths: Remove paths instead of keeping them (used with `--path`).
    --replace-text <file>: Apply text replacement rules loaded from a config file (supports regex).
    --refs <pattern>: Limit rewriting to matching refs such as `refs/heads/main`.
    --dry-run: Simulate the rewrite and report planned changes without modifying the repo.

  Example Usage:
    * `git filter-repo --path docs/` — Extract the documentation history into a standalone repository.
    * `git filter-repo --invert-paths --path secrets/` — Remove a sensitive directory from all commits.
    * `git filter-repo --replace-text mappings.txt` — Scrub API keys or credentials according to a mapping file.
*/

{
  flake.nixosModules.apps.git-filter-repo =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."git-filter-repo" ];
    };

}
