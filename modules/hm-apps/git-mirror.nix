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
      inherit (cfg) firefoxDocs pythonDocs;
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
        rawName
        |> sanitizeUrlDirName
        |> collapseDashes
        |> trimDashes;
      mirrorDirName =
        spec:
        if lib.hasPrefix "http://" spec || lib.hasPrefix "https://" spec then
          urlToDirName spec
        else
          builtins.replaceStrings [ "/" ] [ "-" ] spec;
      onSuccessUnits =
        lib.optionals firefoxDocs.enable [ "git-mirror-firefox-docs.service" ]
        ++ lib.optionals pythonDocs.enable [ "git-mirror-python-docs.service" ];
      firefoxDocsLockPath = "${firefoxDocs.repoPath}.git-mirror.lock";
      pythonDocsLockPath = "${pythonDocs.outputRoot}.git-mirror.lock";
      reposFile = pkgs.writeText "repos.txt" (lib.concatStringsSep "\n" cfg.repos);

      # Helper script for syncing a single repo (called by parallel)
      syncRepoScript = pkgs.writeShellApplication {
        name = "git-mirror-sync-repo";
        runtimeInputs = with pkgs; [
          git
          coreutils
          gawk
          util-linux
        ];
        text = ''
          set -eu
          spec="$1"
          max_backups="$GIT_MIRROR_MAX_BACKUPS"

          log() { printf '%s %s\n' "$(date -Is)" "$*" >&2; }

          retry_git() {
            label="$1"
            shift
            attempt=1
            delay=15

            while true; do
              if "$@"; then
                return 0
              else
                status="$?"
              fi
              if [ "$attempt" -ge 3 ]; then
                log "$spec: $label failed after $attempt attempts"
                return "$status"
              fi

              log "$spec: $label failed (attempt $attempt/3), retrying in ''${delay}s"
              sleep "$delay"
              attempt=$((attempt + 1))
              delay=$((delay * 2))
            done
          }

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

          if [ "''${GIT_MIRROR_FIREFOX_DOCS_REPO_SPEC:-}" = "$spec" ] && [ -n "''${GIT_MIRROR_FIREFOX_DOCS_LOCK_PATH:-}" ]; then
            lock_file="$GIT_MIRROR_FIREFOX_DOCS_LOCK_PATH"
            mkdir -p "$(dirname "$lock_file")"
            exec 9>"$lock_file"
            flock 9
          fi

          log "$spec: syncing"

          # Clone if missing
          if [ ! -d "$dir" ]; then
            retry_git "clone" git clone "$url" "$dir" || exit 1
            chmod g+s "$dir" || { log "$spec: chmod failed"; exit 1; }
            log "$spec: cloned"
            exit 0
          fi

          [ -d "$dir/.git" ] || { log "$spec: not a git repo"; exit 1; }

          retry_git "fetch" git -C "$dir" remote update --prune || exit 1

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
          lockPath = firefoxDocsLockPath;
        };
      };

      pythonDocsScript = import ./_python-docs-publisher.nix {
        inherit lib pkgs;
        pythonDocs = pythonDocs // {
          lockPath = pythonDocsLockPath;
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
        ];
        text = ''
          set -eu
          umask 002
          export GIT_MIRROR_ROOT="${cfg.root}"
          export GIT_MIRROR_MAX_BACKUPS=${toString cfg.maxBackups}
          ${lib.optionalString firefoxDocs.enable ''
            export GIT_MIRROR_FIREFOX_DOCS_REPO_SPEC=${lib.escapeShellArg firefoxDocs.repoSpec}
            export GIT_MIRROR_FIREFOX_DOCS_LOCK_PATH=${lib.escapeShellArg firefoxDocsLockPath}
          ''}
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
            default = "${cfg.root}/${mirrorDirName firefoxDocs.repoSpec}-docs";
            description = "Directory where generated Firefox source docs are published. Defaults to the mirror path derived from repoSpec with a -docs suffix.";
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

        pythonDocs = {
          enable = lib.mkEnableOption "publishing current stable Python documentation sources after mirror sync";

          repoSpec = lib.mkOption {
            type = lib.types.str;
            default = "python/cpython";
            description = "Repository spec from programs.gitMirror.repos that provides CPython documentation sources.";
          };

          repoPath = lib.mkOption {
            type = lib.types.str;
            default = "${cfg.root}/${mirrorDirName pythonDocs.repoSpec}";
            description = "Local CPython checkout used as the Python documentation source repository. Defaults to the mirror path derived from repoSpec.";
          };

          outputRoot = lib.mkOption {
            type = lib.types.str;
            default = "${cfg.root}/${mirrorDirName pythonDocs.repoSpec}-docs";
            description = "Directory where current stable Python documentation sources are published. Defaults to the mirror path derived from repoSpec with a -docs suffix.";
          };

          versionUrl = lib.mkOption {
            type = lib.types.str;
            default = "https://docs.python.org/3/";
            description = "Python documentation URL used to resolve the current stable CPython minor branch.";
          };

          maxRevisions = lib.mkOption {
            type = lib.types.ints.positive;
            default = 2;
            description = "Maximum published Python documentation source revisions to keep.";
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
            assertion = builtins.length cfg.repos == builtins.length (lib.unique cfg.repos);
            message = "programs.gitMirror.repos must not contain duplicate entries.";
          }
          {
            assertion = !firefoxDocs.enable || builtins.elem firefoxDocs.repoSpec cfg.repos;
            message = "programs.gitMirror.firefoxDocs.repoSpec must be present in programs.gitMirror.repos.";
          }
          {
            assertion = !pythonDocs.enable || builtins.elem pythonDocs.repoSpec cfg.repos;
            message = "programs.gitMirror.pythonDocs.repoSpec must be present in programs.gitMirror.repos.";
          }
        ];

        home.packages = [
          mirrorScript
        ]
        ++ lib.optional firefoxDocs.enable firefoxDocsScript
        ++ lib.optional pythonDocs.enable pythonDocsScript;

        systemd.user = {
          services = {
            git-mirror = {
              Unit = {
                Description = "Sync git mirrors";
                X-SwitchMethod = "keep-old";
                StartLimitBurst = 3;
                StartLimitIntervalSec = "1h";
              }
              // lib.optionalAttrs (onSuccessUnits != [ ]) {
                OnSuccess = onSuccessUnits;
              };
              Service = {
                Type = "oneshot";
                ExecStart = "${mirrorScript}/bin/git-mirror";
                Environment = [ "GIT_TERMINAL_PROMPT=0" ];
                Restart = "on-failure";
                RestartSec = "5m";
              };
            };

            git-mirror-firefox-docs = lib.mkIf firefoxDocs.enable {
              Unit = {
                Description = "Build Firefox source docs";
                After = [ "git-mirror.service" ];
                X-SwitchMethod = "keep-old";
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

            git-mirror-python-docs = lib.mkIf pythonDocs.enable {
              Unit = {
                Description = "Publish current stable Python documentation sources";
                After = [ "git-mirror.service" ];
                X-SwitchMethod = "keep-old";
              };
              Service = {
                Type = "oneshot";
                ExecStart = "${pythonDocsScript}/bin/git-mirror-publish-python-docs";
                Environment = [ "GIT_TERMINAL_PROMPT=0" ];
                TimeoutStartSec = "30m";
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
