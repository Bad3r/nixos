/*
  Package: act
  Description: Run GitHub Actions locally in containers through the Docker API.
  Homepage: https://nektosact.com/
  Documentation: https://nektosact.com/usage/index.html
  Repository: https://github.com/nektos/act

  Summary:
    * Executes GitHub Actions workflows locally in runner containers on any Docker API engine.
    * Supports platform image mapping, secret injection, and dry-run mode.

  Options:
    -l: List available workflows and jobs.
    -n: Dry-run mode (skip execution).
    -j <job>: Run a specific job.
    -W <path>: Specify workflows directory.
    -P <platform>=<image>: Map a platform to a container image.

  Notes:
    * Installs a wrapper that passes the gh CLI's token as the GITHUB_TOKEN secret and fails when gh is logged out.
    * The wrapper passes through untouched when the caller sets GITHUB_TOKEN with -s/--secret or passes --secret-file.
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

      act = lib.getExe cfg.package;

      wrappedAct = pkgs.writeShellApplication {
        name = "act";
        text = ''
          prev=""
          for arg in "$@"; do
            name="''${arg^^}"
            case "$prev" in
              -s | --secret) name="--SECRET=$name" ;;
            esac
            case "$name" in
              --SECRET-FILE | --SECRET-FILE=* | --SECRET=GITHUB_TOKEN | --SECRET=GITHUB_TOKEN=* | -SGITHUB_TOKEN | -SGITHUB_TOKEN=*)
                exec ${act} "$@"
                ;;
            esac
            prev="$arg"
          done

          if ! token="$(${lib.getExe pkgs.gh} auth token)" || [ -z "$token" ]; then
            echo "act: no GitHub token from 'gh auth token'; run 'gh auth login', or pass -s GITHUB_TOKEN or --secret-file" >&2
            exit 1
          fi
          # -s without a value makes act read the secret from the environment, keeping it out of argv.
          export GITHUB_TOKEN="$token"
          exec ${act} -s GITHUB_TOKEN "$@"
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

        # The Docker API engine behind /run/docker.sock.
        programs.podman.extended.enable = lib.mkOverride 1050 true;
      };
    };
in
{
  flake.nixosModules.apps.act = ActModule;
}
