/*
  Syncs GitHub repositories to a flat /data/git/{owner}-{repo} structure.
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

      # Helper script for syncing a single repo (called by parallel)
      syncRepoScript = pkgs.writeShellApplication {
        name = "git-mirror-sync-repo";
        runtimeInputs = with pkgs; [
          git
          coreutils
          gawk
        ];
        text = ''
          set -eu
          spec="$1"
          dir="$GIT_MIRROR_ROOT/$(printf '%s' "$spec" | tr '/' '-')"
          url="https://github.com/$spec.git"
          max_backups="$GIT_MIRROR_MAX_BACKUPS"

          log() { printf '%s %s\n' "$(date -Is)" "$*" >&2; }

          log "$spec: syncing"

          # Clone if missing
          if [ ! -d "$dir" ]; then
            git clone "$url" "$dir" && chmod g+s "$dir"
            log "$spec: cloned"
            exit 0
          fi

          [ -d "$dir/.git" ] || { log "$spec: not a git repo"; exit 1; }

          git -C "$dir" remote update --prune || { log "$spec: fetch failed"; exit 1; }

          # Stash dirty work
          if [ -n "$(git -C "$dir" status -s)" ]; then
            git -C "$dir" stash push -u -m "git-mirror: $(date -u +%Y%m%dT%H%M%SZ)" || true
            # Prune old stashes (reverse order to avoid index shifting)
            git -C "$dir" stash list | awk -F: '/git-mirror:/ {print $1}' | tail -n +"$((max_backups + 1))" | \
              tac | xargs -r -I{} git -C "$dir" stash drop {} 2>/dev/null || true
          fi

          # Get tracking branch
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
                refs/heads/git-mirror/backup-* | tail -n +"$((max_backups + 1))" | \
                xargs -r -I{} git -C "$dir" branch -D {} 2>/dev/null || true
            fi
            git -C "$dir" reset --hard "$tracking"
          fi

          git -C "$dir" clean -fdx >/dev/null
          log "$spec: up to date"
        '';
      };

      # Main entry point
      mirrorScript = pkgs.writeShellApplication {
        name = "git-mirror";
        runtimeInputs = with pkgs; [
          coreutils
          gnugrep
          parallel
          syncRepoScript
        ];
        text = ''
          set -eu
          umask 002
          export GIT_MIRROR_ROOT="${cfg.root}"
          export GIT_MIRROR_MAX_BACKUPS=${toString cfg.maxBackups}
          grep -vE '^[[:space:]]*(#|$)' "${reposFile}" | \
            parallel --line-buffer -j${toString cfg.jobs} ${syncRepoScript}/bin/git-mirror-sync-repo
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
          default = [
            "cachix/git-hooks.nix"
          ];
          example = [
            "NixOS/nixpkgs"
            "nix-community/home-manager"
            "better-auth/better-auth"
            "openai/codex"
            "cachix/git-hooks.nix"
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
