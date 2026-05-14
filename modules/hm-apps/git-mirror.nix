/*
  Syncs Git repositories to a flat /data/git structure.
  GitHub owner/repo specs use /data/git/{owner}-{repo}; URL specs include
  the normalized host prefix, e.g. /data/git/codeberg-librewolf-settings.
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
      inherit (cfg) firefoxDocs;
      allowedUrlDirChars = lib.stringToCharacters "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-";
      stripAfter = separator: value: builtins.head (lib.splitString separator value);
      sanitizeUrlDirName =
        value:
        lib.concatMapStrings (char: if builtins.elem char allowedUrlDirChars then char else "-") (
          lib.stringToCharacters value
        );
      collapseDashes =
        value:
        let
          next = builtins.replaceStrings [ "--" ] [ "-" ] value;
        in
        if next == value then value else collapseDashes next;
      trimDashes = value: lib.removePrefix "-" (lib.removeSuffix "-" value);
      urlToDirName =
        spec:
        let
          withoutScheme = lib.removePrefix "http://" (lib.removePrefix "https://" spec);
          withoutQuery = stripAfter "#" (stripAfter "?" withoutScheme);
          normalized = lib.removeSuffix ".git" (lib.removeSuffix "/" withoutQuery);
          parts = lib.filter (part: part != "") (lib.splitString "/" normalized);
          host = if parts == [ ] then "" else builtins.head parts;
          hostName =
            host
            |> lib.removePrefix "www."
            |> lib.removeSuffix ".com"
            |> lib.removeSuffix ".org"
            |> lib.removeSuffix ".net";
          pathParts = if parts == [ ] then [ ] else builtins.tail parts;
          rawName = lib.concatStringsSep "-" ([ hostName ] ++ pathParts);
        in
        rawName |> sanitizeUrlDirName |> collapseDashes |> trimDashes;
      mirrorDirName =
        spec:
        if lib.hasPrefix "http://" spec || lib.hasPrefix "https://" spec then
          urlToDirName spec
        else
          builtins.replaceStrings [ "/" ] [ "-" ] spec;
      mirrorLockPath = "${cfg.root}/.git-mirror.lock";
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
          max_backups="$GIT_MIRROR_MAX_BACKUPS"

          log() { printf '%s %s\n' "$(date -Is)" "$*" >&2; }

          url_to_dir_name() {
            printf '%s\n' "$1" | awk '
              {
                value = $0
                sub(/^[[:alpha:]][[:alnum:].+-]*:\/\//, "", value)
                sub(/[?#].*$/, "", value)
                sub(/\/$/, "", value)
                sub(/\.git$/, "", value)
                count = split(value, parts, "/")
                host = parts[1]
                sub(/^www\./, "", host)
                sub(/\.(com|org|net)$/, "", host)
                output = host
                for (i = 2; i <= count; i++) {
                  if (parts[i] != "") {
                    output = output "-" parts[i]
                  }
                }
                gsub(/[^[:alnum:]._-]/, "-", output)
                gsub(/-+/, "-", output)
                gsub(/^-|-$/, "", output)
                print output
              }'
          }

          case "$spec" in
            http://*|https://*)
              url="$spec"
              dir="$GIT_MIRROR_ROOT/$(url_to_dir_name "$spec")"
              ;;
            *)
              url="https://github.com/$spec.git"
              dir="$GIT_MIRROR_ROOT/$(printf '%s' "$spec" | tr '/' '-')"
              ;;
          esac

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

      firefoxDocsScript = import ./_firefox-docs-builder.nix {
        inherit lib pkgs;
        firefoxDocs = firefoxDocs // {
          lockPath = mirrorLockPath;
        };
      };

      # Main entry point
      mirrorScript = pkgs.writeShellApplication {
        name = "git-mirror";
        runtimeInputs = with pkgs; [
          coreutils
          gnugrep
          parallel
          syncRepoScript
          util-linux
        ];
        text = ''
          set -eu
          umask 002
          lock_file=${lib.escapeShellArg mirrorLockPath}
          mkdir -p "$(dirname "$lock_file")"
          exec 9>"$lock_file"
          flock 9

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
          description = "Directory for mirrored repositories.";
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
            "https://codeberg.org/librewolf/settings.git"
          ];
          description = "Repositories to mirror as GitHub owner/repo shorthand or full HTTP(S) Git URLs.";
        };

        firefoxDocs = {
          enable = lib.mkEnableOption "building Firefox source documentation after mirror sync";

          repoSpec = lib.mkOption {
            type = lib.types.str;
            default = "mozilla-firefox/firefox";
            description = "Repository spec from programs.gitMirror.repos that provides Firefox source docs.";
          };

          repoPath = lib.mkOption {
            type = lib.types.str;
            default = "${cfg.root}/${mirrorDirName firefoxDocs.repoSpec}";
            description = "Local Firefox checkout used as the mach doc source tree. Defaults to the mirror path derived from repoSpec.";
          };

          outputRoot = lib.mkOption {
            type = lib.types.str;
            default = "${cfg.root}/mozilla-firefox-firefox-docs";
            description = "Directory where generated Firefox source docs are published.";
          };

          maxRevisions = lib.mkOption {
            type = lib.types.ints.positive;
            default = 2;
            description = "Maximum generated Firefox documentation revisions and linkcheck outputs to keep.";
          };

          format = lib.mkOption {
            type = lib.types.str;
            default = "html";
            description = "Sphinx builder format passed to mach doc.";
          };

          path = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional Firefox documentation path passed to mach doc.";
          };

          jobs = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.positive;
            default = null;
            description = "Optional parallelism value passed to mach doc with -j.";
          };

          archive = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether to ask mach doc to write a tarball of the generated docs.";
          };

          linkcheck = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether to run a second mach doc linkcheck pass after generating HTML docs.";
          };

          noAutodoc = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether to pass --no-autodoc to mach doc.";
          };

          disableWarningsCheck = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether to pass --disable-warnings-check to mach doc.";
          };

          verbose = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether to pass --verbose to mach doc.";
          };
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
        assertions = [
          {
            assertion = !firefoxDocs.enable || builtins.elem firefoxDocs.repoSpec cfg.repos;
            message = "programs.gitMirror.firefoxDocs.repoSpec must be present in programs.gitMirror.repos.";
          }
        ];

        home.packages = [ mirrorScript ] ++ lib.optional firefoxDocs.enable firefoxDocsScript;

        systemd.user = {
          services = {
            git-mirror = {
              Unit = {
                Description = "Sync git mirrors";
              }
              // lib.optionalAttrs firefoxDocs.enable {
                Wants = [ "git-mirror-firefox-docs.service" ];
              };
              Service = {
                Type = "oneshot";
                ExecStart = "${mirrorScript}/bin/git-mirror";
                Environment = [ "GIT_TERMINAL_PROMPT=0" ];
              };
            };

            git-mirror-firefox-docs = lib.mkIf firefoxDocs.enable {
              Unit = {
                Description = "Build Firefox source docs";
                After = [ "git-mirror.service" ];
              };
              Service = {
                Type = "oneshot";
                ExecStart = "${firefoxDocsScript}/bin/git-mirror-build-firefox-docs";
                Environment = [ "GIT_TERMINAL_PROMPT=0" ];
                TimeoutStartSec = "6h";
                Nice = 10;
                IOSchedulingClass = "idle";
              };
            };
          };

          timers.git-mirror = {
            Unit.Description = "Git mirror sync timer";
            Timer = {
              OnCalendar = cfg.timer;
              Persistent = true;
            };
            Install.WantedBy = [ "timers.target" ];
          };
        };
      };
    };
}
