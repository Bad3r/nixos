/*
  Syncs GitHub repositories to a flat /git/{owner}-{repo} structure.
  Preserves local work via stash/backup before resetting to upstream.
*/
{
  flake.homeManagerModules.apps."git-mirror" =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.programs.gitMirror;
      reposFile = pkgs.writeText "repos.txt" (lib.concatStringsSep "\n" cfg.repos);

      mirrorScript = pkgs.writeShellApplication {
        name = "git-mirror";
        runtimeInputs = with pkgs; [
          git
          coreutils
          gnugrep
          gawk
          parallel
        ];
        text = ''
          set -euo pipefail
          umask 002

          export root="${cfg.root}"
          export max_backups=${toString cfg.maxBackups}
          export jobs=${toString cfg.jobs}

          log() { printf '%s %s\n' "$(date -Is)" "$*" >&2; }
          export -f log

          spec_to_dir() { printf '%s' "''${1//\//-}"; }
          export -f spec_to_dir

          sync_repo() {
            local spec dir url
            spec="$1"
            dir="$root/$(spec_to_dir "$spec")"
            url="https://github.com/$spec.git"

            log "$spec: syncing"

            # Clone if missing
            if [ ! -d "$dir" ]; then
              git clone "$url" "$dir" && chmod g+s "$dir"
              log "$spec: cloned"
              return 0
            fi

            [ -d "$dir/.git" ] || { log "$spec: not a git repo"; return 1; }

            git -C "$dir" remote update --prune || { log "$spec: fetch failed"; return 1; }

            # Stash dirty work
            if [ -n "$(git -C "$dir" status -s)" ]; then
              git -C "$dir" stash push -u -m "git-mirror: $(date -u +%Y%m%dT%H%M%SZ)" || true
              # Prune old stashes (reverse order to avoid index shifting)
              git -C "$dir" stash list | awk -F: '/git-mirror:/ {print $1}' | tail -n +$((max_backups + 1)) | \
                tac | xargs -r -I{} git -C "$dir" stash drop {} 2>/dev/null || true
            fi

            # Get tracking branch
            local tracking local_sha remote_sha base_sha
            tracking=$(git -C "$dir" rev-parse --abbrev-ref '@{u}' 2>/dev/null) || \
              tracking="origin/$(git -C "$dir" remote show origin | awk '/HEAD branch/ {print $3}')"

            local_sha=$(git -C "$dir" rev-parse HEAD)
            remote_sha=$(git -C "$dir" rev-parse "$tracking")

            if [ "$local_sha" != "$remote_sha" ]; then
              # Backup diverging history
              base_sha=$(git -C "$dir" merge-base HEAD "$tracking" 2>/dev/null || true)
              if [ -z "$base_sha" ] || [ "$base_sha" != "$remote_sha" ]; then
                git -C "$dir" branch "git-mirror/backup-$(date -u +%Y%m%dT%H%M%SZ)" 2>/dev/null || true
                # Prune old backups
                git -C "$dir" for-each-ref --sort=-committerdate --format='%(refname:short)' \
                  refs/heads/git-mirror/backup-* | tail -n +$((max_backups + 1)) | \
                  xargs -r -I{} git -C "$dir" branch -D {} 2>/dev/null || true
              fi
              git -C "$dir" reset --hard "$tracking"
            fi

            git -C "$dir" clean -fdx >/dev/null
            log "$spec: up to date"
          }
          export -f sync_repo

          mapfile -t repos < <(grep -vE '^[[:space:]]*(#|$)' "${reposFile}")
          printf '%s\n' "''${repos[@]}" | parallel --line-buffer -j"$jobs" sync_repo
        '';
      };
    in
    {
      options.programs.gitMirror = {
        enable = lib.mkEnableOption "git mirror sync";

        root = lib.mkOption {
          type = lib.types.str;
          default = "/data/git";
          description = "Directory for mirrored repos (flat {owner}-{repo} structure).";
        };

        repos = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [
            "NixOS/nixpkgs"
            "nix-community/home-manager"
          ];
          description = "GitHub repos to mirror (owner/repo format).";
        };

        maxBackups = lib.mkOption {
          type = lib.types.ints.positive;
          default = 5;
          description = "Max stashes/backup branches to keep per repo.";
        };

        jobs = lib.mkOption {
          type = lib.types.ints.positive;
          default = 4;
          description = "Number of parallel sync jobs.";
        };

        timer = lib.mkOption {
          type = lib.types.str;
          default = "daily";
          description = "Systemd calendar expression for sync schedule.";
        };
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ mirrorScript ];

        systemd.user.services.git-mirror = {
          Unit.Description = "Sync git mirrors";
          Service = {
            Type = "oneshot";
            ExecStart = "${mirrorScript}/bin/git-mirror";
            Environment = [ "GIT_TERMINAL_PROMPT=0" ];
          };
        };

        systemd.user.timers.git-mirror = {
          Unit.Description = "Git mirror sync timer";
          Timer = {
            OnCalendar = cfg.timer;
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}
