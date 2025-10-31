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
  config,
  lib,
  pkgs,
  ...
}:
let
  ForgitModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.forgit.extended;
    in
    {
      options.programs.forgit.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable forgit.";
        };

        package = lib.mkPackageOption pkgs "zsh-forgit" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.forgit = ForgitModule;
}
