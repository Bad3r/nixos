/*
  Package: act
  Description: Run GitHub Actions locally using Docker containers.
  Homepage: https://nektosact.com/
  Documentation: https://nektosact.com/usage/index.html
  Repository: https://github.com/nektos/act

  Summary:
    * Executes GitHub Actions workflows locally with Docker-based runners.
    * Supports platform image mapping, secret injection, and dry-run mode.

  Options:
    -l: List available workflows and jobs.
    -n: Dry-run mode (skip execution).
    -j <job>: Run a specific job.
    -W <path>: Specify workflows directory.
    -P <platform>=<image>: Map a platform to a Docker image.

  Notes:
    * Installs a wrapper that auto-injects --secret-file /etc/act/secrets.env when the file exists.
    * The wrapper passes through to the unwrapped binary when --secret-file is already provided.
*/
_:
let
  ActModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.act.extended;

      secretsFile = "/etc/act/secrets.env";

      # Wrap act to auto-inject --secret-file when available
      wrappedAct = pkgs.writeShellApplication {
        name = "act";
        runtimeInputs = [ cfg.package ];
        text = ''
          # Auto-inject secrets unless --secret-file is already provided
          for arg in "$@"; do
            if [ "$arg" = "--secret-file" ]; then
              exec ${lib.getExe cfg.package} "$@"
            fi
          done

          if [ -f "${secretsFile}" ]; then
            exec ${lib.getExe cfg.package} --secret-file "${secretsFile}" "$@"
          fi

          exec ${lib.getExe cfg.package} "$@"
        '';
      };
    in
    {
      options.programs.act.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable act.";
        };

        package = lib.mkPackageOption pkgs "act" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ wrappedAct ];
      };
    };
in
{
  flake.nixosModules.apps.act = ActModule;
}
