/*
  Package: ghq-mirror
  Description: Declarative ghq mirror management with conflict-safe updates.
  Homepage: https://github.com/x-motemen/ghq
  Repository: https://github.com/x-motemen/ghq

  Summary:
    * Installs ghq alongside GitHub CLI helpers and keeps a shared mirror tree in sync.
    * Preserves local work by stashing or snapshotting diverging history before resetting.
    * Rotates stashes and backup branches to the newest five entries to avoid unbounded growth.
*/

{
  flake.homeManagerModules.apps."ghq-mirror" =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.programs.ghqMirror;
      ghBin = "${pkgs.gh}/bin/gh";
      reposText = lib.concatStringsSep "\n" (cfg.repos ++ [ "" ]);
      reposFile = pkgs.writeText "ghq-mirror-repos.txt" reposText;
      runtimePath = lib.makeBinPath (
        with pkgs;
        [
          coreutils
          gnugrep
          gawk
          gnused
          findutils
          git
          ghq
        ]
      );
      ghqMirrorScript = pkgs.writeShellApplication {
        name = "ghq-mirror";
        runtimeInputs = [ ];
        text = ''
                    set -euo pipefail

                    umask 002

                    root="''${GHQ_ROOT:-/git}"
                    repos_file=""
                    max_backups=5

                    usage() {
                      cat <<'EOF'
          ghq-mirror --root /git --repos-file repos.txt [--max-backups 5]

          Synchronise ghq-managed repositories while preserving local changes.
          EOF
                    }

                    while [ "$#" -gt 0 ]; do
                      case "$1" in
                        --root)
                          root="$2"
                          shift 2
                          ;;
                        --repos-file)
                          repos_file="$2"
                          shift 2
                          ;;
                        --max-backups)
                          max_backups="$2"
                          shift 2
                          ;;
                        -h|--help)
                          usage
                          exit 0
                          ;;
                        *)
                          echo "ghq-mirror: unknown option '$1'" >&2
                          exit 2
                          ;;
                      esac
                    done

                    if ! [[ "$max_backups" =~ ^[0-9]+$ ]]; then
                      echo "ghq-mirror: --max-backups must be numeric" >&2
                      exit 2
                    fi

                    if [ -z "$repos_file" ]; then
                      echo "ghq-mirror: --repos-file is required" >&2
                      exit 2
                    fi

                    if [ ! -r "$repos_file" ]; then
                      echo "ghq-mirror: repos file '$repos_file' not readable" >&2
                      exit 1
                    fi

                    if [ ! -d "$root" ]; then
                      echo "ghq-mirror: shared root '$root' is missing" >&2
                      exit 1
                    fi

                    export GHQ_ROOT="$root"
                    export PATH="${runtimePath}:$PATH"
                    export GIT_TERMINAL_PROMPT=0

                    log() {
                      printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" >&2
                    }

                    readarray -t repos < <(grep -vE '^[[:space:]]*(#|$)' "$repos_file")

                    if [ ''${#repos[@]} -eq 0 ]; then
                      log "no repositories defined; exiting"
                      exit 0
                    fi

                    ghq_bin="${pkgs.ghq}/bin/ghq"
                    git_bin="${pkgs.git}/bin/git"

                    resolve_path() {
                      local spec="$1"
                      local path
                      path="$($ghq_bin list --full-path --exact "$spec" 2>/dev/null | head -n1 || true)"
                      if [ -z "$path" ] && [[ "$spec" != *:* ]]; then
                      path="$($ghq_bin list --full-path --exact "github.com/''${spec}" 2>/dev/null | head -n1 || true)"
                      fi
                      if [ -z "$path" ] && [ -d "$root/github.com/''${spec}" ]; then
                        path="$root/github.com/''${spec}"
                      fi
                      printf '%s' "$path"
                    }

                    prune_stashes() {
                      local repo="$1"
                      local -a stashes
                      readarray -t stashes < <($git_bin -C "$repo" stash list | awk -F: '/ghq-sync:/ {print $1}' || true)
                      local count=''${#stashes[@]}
                      if [ "$count" -le "$max_backups" ]; then
                        return 0
                      fi
                      local idx
                      for (( idx = count - 1; idx >= max_backups; idx-- )); do
                        $git_bin -C "$repo" stash drop ''${stashes[$idx]} >/dev/null 2>&1 || true
                      done
                    }

                    prune_branches() {
                      local repo="$1"
                      local -a branches
                      readarray -t branches < <($git_bin -C "$repo" for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads/ghq-sync/backup-* 2>/dev/null || true)
                      local count=''${#branches[@]}
                      if [ "$count" -le "$max_backups" ]; then
                        return 0
                      fi
                      local idx
                      for (( idx = max_backups; idx < count; idx++ )); do
                        $git_bin -C "$repo" branch -D ''${branches[$idx]} >/dev/null 2>&1 || true
                      done
                    }

                    snapshot_history() {
                      local repo="$1"
                      local spec="$2"
                      local stamp
                      stamp="$(date -u +%Y%m%dT%H%M%SZ)"
                      local branch="ghq-sync/backup-''${stamp}"
                      if $git_bin -C "$repo" branch "$branch" >/dev/null 2>&1; then
                        log "$spec: saved diverging history to $branch"
                        prune_branches "$repo"
                      else
                        log "$spec: failed to create backup branch $branch"
                      fi
                    }

                    ensure_clean_worktree() {
                      local repo="$1"
                      local spec="$2"
                      if [ -n "$($git_bin -C "$repo" status --short)" ]; then
                        local stamp
                        stamp="$(date -u +%Y%m%dT%H%M%SZ)"
                        if $git_bin -C "$repo" stash push --include-untracked --message "ghq-sync: ''${stamp}" >/dev/null 2>&1; then
                          log "$spec: staged dirty worktree into stash"
                          prune_stashes "$repo"
                        else
                          log "$spec: failed to stash dirty worktree"
                        fi
                      fi
                    }

                    default_tracking() {
                      local repo="$1"
                      local head
                      head="$($git_bin -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
                      if [ -n "$head" ]; then
                        printf '%s' "$head"
                        return 0
                      fi
                      local branch
                      branch="$($git_bin -C "$repo" remote show origin 2>/dev/null | awk '/HEAD branch/ {print $3}' | head -n1 || true)"
                      if [ -n "$branch" ]; then
                        printf 'origin/%s' "$branch"
                      fi
                    }

                    reconcile_repo() {
                      local spec="$1"
                      log "$spec: syncing"
                      if ! $ghq_bin get --update "$spec" >/dev/null 2>&1; then
                        log "$spec: ghq get failed"
                        return 1
                      fi

                      local repo_path
                      repo_path="$(resolve_path "$spec")"
                      if [ -z "$repo_path" ]; then
                        log "$spec: unable to resolve clone path"
                        return 1
                      fi

                      if [ ! -d "$repo_path/.git" ]; then
                        log "$spec: missing .git directory"
                        return 1
                      fi

                      chmod g+s "$repo_path" >/dev/null 2>&1 || true

                      if ! $git_bin -C "$repo_path" remote update --prune >/dev/null 2>&1; then
                        log "$spec: remote update failed"
                        return 1
                      fi

                      ensure_clean_worktree "$repo_path" "$spec"

                      local tracking
                      tracking="$(default_tracking "$repo_path")"
                      if [ -z "$tracking" ]; then
                        log "$spec: unable to determine tracking branch"
                        return 1
                      fi

                      if ! $git_bin -C "$repo_path" rev-parse "$tracking" >/dev/null 2>&1; then
                        log "$spec: tracking ref '$tracking' missing"
                        return 1
                      fi

                      local local_sha
                      local remote_sha
                      local base_sha
                      local_sha="$($git_bin -C "$repo_path" rev-parse HEAD)"
                      remote_sha="$($git_bin -C "$repo_path" rev-parse "$tracking")"
                      base_sha="$($git_bin -C "$repo_path" merge-base HEAD "$tracking" 2>/dev/null || true)"

                      if [ "$local_sha" != "$remote_sha" ]; then
                        if [ -z "$base_sha" ] || [ "$base_sha" != "$remote_sha" ]; then
                          snapshot_history "$repo_path" "$spec"
                        fi
                        if ! $git_bin -C "$repo_path" reset --hard "$tracking" >/dev/null 2>&1; then
                          log "$spec: failed to reset to $tracking"
                          return 1
                        fi
                      fi

                      $git_bin -C "$repo_path" clean -fdx >/dev/null 2>&1 || true
                      log "$spec: up to date"
                    }

                    rc=0
                    for spec in "''${repos[@]}"; do
                      if ! reconcile_repo "$spec"; then
                        rc=1
                      fi
                    done

                    exit "$rc"
        '';
      };
      runner = pkgs.writeShellScript "ghq-mirror-service" ''
        exec ${ghqMirrorScript}/bin/ghq-mirror \
          --root ${lib.escapeShellArg cfg.root} \
          --repos-file ${lib.escapeShellArg reposFile} \
          --max-backups ${toString cfg.maxBackups}
      '';
    in
    {
      options.programs.ghqMirror = {
        enable = lib.mkEnableOption "automatic ghq mirroring";

        root = lib.mkOption {
          type = lib.types.str;
          default = "/git";
          description = "Shared ghq root path. Should match system ghq root.";
        };

        repos = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [
            "nix-community/home-manager"
            "nix-community/nixvim"
          ];
          description = "GitHub repositories (`owner/name`) to keep mirrored locally.";
        };

        maxBackups = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 5;
          description = "Maximum number of stashes and backup branches to retain.";
        };

        timer = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable the systemd timer that periodically refreshes mirrors.";
          };

          onCalendar = lib.mkOption {
            type = lib.types.str;
            default = "daily";
            description = "systemd OnCalendar expression that schedules mirror refreshes.";
          };
        };

        installExtension = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Ensure the 'gh-q' GitHub CLI extension is installed and updated.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.maxBackups >= 1;
            message = "programs.ghqMirror.maxBackups must be at least 1";
          }
        ];

        home = {
          packages = [
            pkgs.git
            pkgs.gh
            pkgs.ghq
            ghqMirrorScript
          ];

          sessionVariables.GHQ_ROOT = lib.mkDefault cfg.root;

          activation = {
            ghqMirrorBootstrap = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              ${runner}
            '';
          }
          // lib.optionalAttrs cfg.installExtension {
            ghqMirrorExtension = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              export PATH=${runtimePath}:$PATH
              export GH_NO_UPDATE_NOTIFIER=1
              ext_dir="${config.xdg.dataHome}/gh/extensions/gh-q"
              if [ ! -d "$ext_dir" ]; then
                ${ghBin} extension install koki-develop/gh-q || true
              else
                ${ghBin} extension upgrade gh-q || true
              fi
            '';
          };
        };

        programs.git.extraConfig."ghq.root" = lib.mkOverride 10 cfg.root;

        systemd.user.services."ghq-mirror" = {
          Unit = {
            Description = "Refresh ghq mirrors";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            Type = "oneshot";
            Environment = [
              "GH_NO_UPDATE_NOTIFIER=1"
              "GIT_TERMINAL_PROMPT=0"
            ];
            ExecStart = runner;
          };
        };

        systemd.user.timers."ghq-mirror" = lib.mkIf cfg.timer.enable {
          Unit.Description = "Periodic ghq mirror refresh";
          Timer = {
            OnCalendar = cfg.timer.onCalendar;
            Persistent = true;
            AccuracySec = "1h";
          };
          Install.WantedBy = [ "timers.target" ];
        };

      };
    };
}
