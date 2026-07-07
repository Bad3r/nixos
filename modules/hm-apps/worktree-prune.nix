/*
  Scheduled cleanup of local branches whose upstream is gone on the remote,
  together with the worktrees backing them under the configured roots.
  Wraps scripts/prune-stale-worktrees.sh; the timer only ever runs the safe
  --apply mode, never --force. Deleted tips stay recoverable under
  refs/prune-backup/ for backupRetentionDays.
*/
{
  flake.homeManagerModules.apps."worktree-prune" =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.programs.worktreePrune;

      worktreeRemoveSafe = pkgs.writeShellApplication {
        name = "git-worktree-remove-safe";
        runtimeInputs = with pkgs; [
          git
          coreutils
          gnused
        ];
        text = builtins.readFile ../../scripts/git-worktree-remove-safe.sh;
      };

      pruneScript = pkgs.writeShellApplication {
        name = "prune-stale-worktrees";
        runtimeInputs = with pkgs; [
          git
          coreutils
          util-linux
          jq
          worktreeRemoveSafe
        ];
        text = builtins.readFile ../../scripts/prune-stale-worktrees.sh;
      };

      applyArgs = [
        "--apply"
        "--backup-retention-days"
        (toString cfg.backupRetentionDays)
      ]
      ++ lib.concatMap (root: [
        "--root"
        root
      ]) cfg.roots
      ++ lib.concatMap (repo: [
        "--repo"
        repo
      ]) cfg.repos;
    in
    {
      options.programs.worktreePrune = {
        enable = lib.mkEnableOption "scheduled pruning of stale local branches and worktrees";

        roots = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "${config.home.homeDirectory}/trees" ];
          description = "Worktree roots scanned for stale worktrees.";
        };

        repos = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "/home/user/nixos" ];
          description = ''
            Repositories scanned for gone branches even when they have no
            worktree under the roots. Missing paths are reported and skipped.
          '';
        };

        schedule = lib.mkOption {
          type = lib.types.str;
          default = "*-*-01,15 05:00:00";
          description = ''
            Systemd calendar expression for the cleanup timer. systemd has no
            "biweekly" shorthand; the default runs on the 1st and 15th of each
            month for an approximately two-week cadence.
          '';
        };

        backupRetentionDays = lib.mkOption {
          type = lib.types.ints.positive;
          default = 90;
          description = "Days to keep refs/prune-backup/* refs of deleted branches.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.roots != [ ] || cfg.repos != [ ];
            message = "programs.worktreePrune needs at least one root or repo to scan.";
          }
        ];

        home.packages = [ pruneScript ];

        systemd.user = {
          services.worktree-prune = {
            Unit = {
              Description = "Prune stale local branches and worktrees";
              X-SwitchMethod = "keep-old";
            };
            Service = {
              Type = "oneshot";
              ExecStart = "${pruneScript}/bin/prune-stale-worktrees ${lib.escapeShellArgs applyArgs}";
              Environment = [ "GIT_TERMINAL_PROMPT=0" ];
              # Exit 2 means candidates were skipped by a safety check, which
              # is expected on a schedule (dirty WIP trees stay in place).
              SuccessExitStatus = "2";
              TimeoutStartSec = "30m";
            };
          };

          timers.worktree-prune = {
            Unit.Description = "Prune stale local branches and worktrees timer";
            Timer = {
              OnCalendar = cfg.schedule;
              Persistent = true;
            };
            Install.WantedBy = [ "timers.target" ];
          };
        };
      };
    };
}
