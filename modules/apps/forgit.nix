/*
  Package: forgit
  Description: Enhanced Git command wrapper providing fuzzy-finder interfaces for common workflows.
  Homepage: https://github.com/wfxr/forgit
  Documentation: https://github.com/wfxr/forgit#usage
  Repository: https://github.com/wfxr/forgit

  Summary:
    * Adds aliases such as `ga`, `glo`, and `gcb` that open fzf pickers for staging files, browsing commits, and checking out branches.

  Options:
    ga: Pick files to `git add`.
    gcf: Pick files to `git checkout`.
    gco: Pick a commit to check out.
    grl: Browse reflog entries.
    gd: Pick files to view diffs.
*/
_:
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
          description = "Whether to enable forgit.";
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
