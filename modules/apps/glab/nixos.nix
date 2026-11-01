/*
  Package: glab
  Description: Open source GitLab CLI tool bringing GitLab to your terminal.
  Homepage: https://gitlab.com/gitlab-org/cli
  Documentation: https://docs.gitlab.com/cli/
  Repository: https://gitlab.com/gitlab-org/cli

  Summary:
    * Manage issues, merge requests, CI/CD pipelines, and releases from the command line.
    * Supports multiple authenticated GitLab instances with automatic hostname detection.

  Options:
    auth: Manage authentication state (login, logout, status).
    issue: Create, view, list, and manage issues.
    mr: Create, view, and manage merge requests.
    ci: Work with CI/CD pipelines and jobs.
    repo: Clone, fork, and manage repositories.
    release: Create and manage releases.
    config: Manage glab settings and aliases.
*/
_:
let
  GlabModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.glab.extended;
    in
    {
      options.programs.glab.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable glab.";
        };

        package = lib.mkPackageOption pkgs "glab" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.glab = GlabModule;
}
