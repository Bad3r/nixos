/*
  Package: forgit
  Description: Enhanced Git command wrapper providing fuzzy-finder interfaces for common workflows.
  Homepage: https://github.com/wfxr/forgit
  Documentation: https://github.com/wfxr/forgit#usage
  Repository: https://github.com/wfxr/forgit

  Summary:
    * Adds shorthand commands (e.g. `ga`, `gcf`) that invoke fzf-powered pickers for staging hunks, browsing commits, and checking out branches.
    * Ships as a collection of shell scripts compatible with Bash, Zsh, Fish, and Nushell for drop-in Git productivity improvements.

  Options:
    ga: Interactive `git add` staged by selected files or hunks.
    gcf: Launch an fzf picker for `git commit --fixup` targets.
    gco: Choose a branch, tag, or commit to check out via fuzzy search.
    gl: Browse reflog entries interactively before jumping or resetting.
    gd: Select files to view diffs with syntax highlighting.

  Example Usage:
    * `ga` — Stage files or individual hunks after selecting them through fzf.
    * `gco` — Pick a branch interactively to check out without memorizing names.
    * `gl` — Navigate the reflog and jump to previous states using fuzzy search.
*/

{
  flake.nixosModules.apps.forgit =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = [ pkgs.zsh-forgit ];

      programs.zsh.interactiveShellInit = lib.mkAfter ''
        fpath+=(${pkgs.zsh-forgit}/share/zsh/site-functions)
        source ${pkgs.zsh-forgit}/share/zsh/zsh-forgit/forgit.plugin.zsh
      '';
    };
}
