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

      # Single import site: the two docs helpers below receive this function as
      # an argument and render it against their own variables, instead of
      # importing this file themselves or having their variable names spelled here.
      mirrorRootStampGuard = import ./_mirror-root-stamp-guard.nix;

      syncRepoScript = import ./_mirror-sync-repo.nix {
        inherit pkgs;
        mkStampGuard = mirrorRootStampGuard;
      };

      firefoxDocsScript = import ./_firefox-docs-builder.nix {
        inherit lib pkgs;
        mirrorRoot = cfg.root;
        inherit (cfg) stampName;
        mkStampGuard = mirrorRootStampGuard;
        firefoxDocs = firefoxDocs // {
          lockPath = firefoxDocsLockPath;
        };
      };

      pythonDocsScript = import ./_python-docs-publisher.nix {
        inherit lib pkgs;
        mirrorRoot = cfg.root;
        inherit (cfg) stampName;
        mkStampGuard = mirrorRootStampGuard;
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
          export GIT_MIRROR_STAMP_NAME=${lib.escapeShellArg cfg.stampName}
          export GIT_MIRROR_MAX_BACKUPS=${toString cfg.maxBackups}

          # Same two conditions the workers check, once, so an unusable root is
          # one line instead of one per spec. Wording matches the per-spec
          # messages so both read as the same failure. The worker checks stay:
          # they are what stops a clone into a root that goes away mid-run.
          log() { printf '%s git-mirror: %s\n' "$(date -Is)" "$*" >&2; }

          if [ ! -d "$GIT_MIRROR_ROOT" ]; then
            log "mirror root $GIT_MIRROR_ROOT is absent, is the volume mounted?"
            exit 1
          fi

          ${mirrorRootStampGuard {
            rootRef = "$GIT_MIRROR_ROOT";
            stampRef = "$GIT_MIRROR_STAMP_NAME";
          }}

          ${lib.optionalString firefoxDocs.enable ''
            export GIT_MIRROR_FIREFOX_DOCS_REPO_SPEC=${lib.escapeShellArg firefoxDocs.repoSpec}
            export GIT_MIRROR_FIREFOX_DOCS_LOCK_PATH=${lib.escapeShellArg firefoxDocsLockPath}
          ''}
          ${lib.optionalString pythonDocs.enable ''
            export GIT_MIRROR_PYTHON_DOCS_REPO_SPEC=${lib.escapeShellArg pythonDocs.repoSpec}
            export GIT_MIRROR_PYTHON_DOCS_LOCK_PATH=${lib.escapeShellArg pythonDocsLockPath}
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

        stampName = lib.mkOption {
          type = lib.types.str;
          default = ".local-mirrors-root";
          description = ''
            Marker `local-mirrors-root.service` writes inside the root. Every
            sync refuses while it is missing, so it must match
            `localMirrors.stampName`; `modules/hosts/common/mirrors.nix` feeds
            it across.
          '';
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
                Slice = "background.slice";
                IOSchedulingClass = "idle";
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
                Slice = "background.slice";
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
                Slice = "background.slice";
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
