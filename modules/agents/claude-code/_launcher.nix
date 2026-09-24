/*
  Launch wrapper for Claude Code: launch-time env, target-binary selection, and
  routing the shell tool through a controlled bash.

  Unlike codex (which overrides the passwd shell via nss_wrapper), Claude Code
  takes its shell from CLAUDE_CODE_SHELL, so the wrapper sets that variable.
*/
{
  lib,
  pkgs,
  claudePkg,
  bunInstallDir,
  externalBinary,
  installMethods,
}:
let
  rmShim = import ../_rm-shim.nix { inherit lib pkgs; };

  # Full env from the shared source (modules/agents/claude-code/_env.nix),
  # rendered as shell exports; belt-and-suspenders with home.sessionVariables,
  # the binary postFixup, and settings.json `env`.
  claudeEnv = import ./_env.nix;
  envExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") claudeEnv.all
  );
  retiredUnsets = lib.concatMapStringsSep "\n" (name: "unset ${name}") claudeEnv.stripped;
  # Guarded rather than unconditional: claude-rc sets the escape variable to
  # keep DISABLE_TELEMETRY out of the launch, which is what re-enables the
  # GrowthBook evaluation Remote Control requires.
  launchOnlyExports = lib.optionalString (claudeEnv.launchOnly != { }) ''
    if [ -z "''${${claudeEnv.launchOnlyEscape}:-}" ]; then
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: value: "  export ${name}=${lib.escapeShellArg value}"
      ) claudeEnv.launchOnly
    )}
    fi
  '';
  legacyEnvValueUnsets = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: value:
      "if [ \"" + "$" + "{${name}:-}\" = ${lib.escapeShellArg value} ]; then unset ${name}; fi"
    ) claudeEnv.legacyEnvValues
  );

  # Claude runs its shell tool through this via CLAUDE_CODE_SHELL, which requires
  # the path to contain "bash" or "zsh", hence the `bash` name.
  claudeBashWrapper = pkgs.writeShellScriptBin "bash" ''
    set -euo pipefail

    direnvBin=${lib.getExe pkgs.direnv}
    realBash=${lib.getExe pkgs.bashInteractive}
    rmShimPath=${rmShim}/bin/rm

    # Only `rm` lives in this dir, so prepending shadows nothing else; on PATH so
    # bare `rm` is shimmed for every shell invocation form, not just -c below.
    export PATH=${rmShim}/bin''${PATH:+:$PATH}

    # Claude Code runs its shell tool as `bash [OPTS] <command> [ARG...]`. OPTS is
    # any order/mix of short flags (-c, -l, -i, or bundles like -lc) and long
    # flags; newer Claude Code passes login as a separate flag, e.g.
    # `-c -l <command>`, so the command is not always $2. Scan past every option
    # word to find the first operand. A short flag bundle containing `c` selects
    # command mode; long flags (--login, --norc) never do, even when they contain
    # a "c". Non-command invocations (interactive/login shell, no `-c`) are exec'd
    # through untouched.
    originalArgs=("$@")
    options=()
    haveCommand=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --)
          options+=("$1")
          shift
          break
          ;;
        --*)
          options+=("$1")
          shift
          ;;
        -*c*)
          haveCommand=1
          options+=("$1")
          shift
          ;;
        -?*)
          options+=("$1")
          shift
          ;;
        *)
          break
          ;;
      esac
    done

    if [ "$haveCommand" -eq 1 ] && [ "$#" -ge 1 ]; then
      export CLAUDE_WRAPPED_COMMAND="$1"
      shift

      exec "$realBash" "''${options[@]}" '
        # Load direnv as an interactive shell would.
        if direnvExports="$("'"$direnvBin"'" export bash 2>/dev/null)"; then
          eval "$direnvExports"
        fi
        # direnv (e.g. nix-direnv use-flake) can prepend dev-shell bins and
        # push the shim down PATH; re-prepend it so command rm, find -exec rm,
        # xargs rm, and nested shells resolve the shim, not coreutils rm.
        export PATH=${rmShim}/bin''${PATH:+:$PATH}
        rm() {
          "'"$rmShimPath"'" "$@"
        }
        eval "$CLAUDE_WRAPPED_COMMAND"
      ' "$@"
    fi

    exec "$realBash" "''${originalArgs[@]}"
  '';

  # Keep this assignment standalone. packages/tweakcc/shell-wrapper.patch
  # parses it to reach the wrapped Claude executable.
  targetScript =
    if installMethods.bun.enable then
      ''
        target=${lib.escapeShellArg "${bunInstallDir}/bin/claude"}
      ''
    else if installMethods.nix.enable then
      ''
        target=${lib.escapeShellArg "${claudePkg}/bin/claude"}
      ''
    else
      ''
        target=${lib.escapeShellArg externalBinary}
      '';

  wrapperBody = ''
    set -euo pipefail

    ${envExports}
    ${retiredUnsets}
    ${legacyEnvValueUnsets}
    ${launchOnlyExports}

    # Shared scratch root for agent temp files.
    tmpDir="/tmp/agents"
    mkdir -p "$tmpDir"
    export TMPDIR="$tmpDir"

    # Covers Claude itself and any fallback shell (if CLAUDE_CODE_SHELL is
    # rejected); the controlled bash re-asserts the same prepend.
    export PATH=${rmShim}/bin''${PATH:+:$PATH}

    export CLAUDE_CODE_SHELL=${lib.escapeShellArg "${claudeBashWrapper}/bin/bash"}

    ${targetScript}

    if [ ! -x "$target" ]; then
      echo "claude-wrapper: ERROR: Claude Code binary not found or not executable at $target" >&2
      exit 127
    fi

    exec "$target" "$@"
  '';

  claudeWrapped = pkgs.writeShellScriptBin "claude" wrapperBody;

  # Opt-in launcher for `claude rc`. Remote Control is gated on vB() in the
  # 2.1.247 binary, which is false when DISABLE_GROWTHBOOK is set or when x()
  # leaves "default"; x() reads the three names cleared here. Deliberately not
  # the default launcher: it trades the telemetry and nonessential-traffic
  # opt-outs for feature flags. Everything in `binary` still applies.
  claudeRcWrapped = pkgs.writeShellScriptBin "claude-rc" ''
    set -euo pipefail

    unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC DISABLE_TELEMETRY DO_NOT_TRACK
    unset DISABLE_GROWTHBOOK
    export ${claudeEnv.launchOnlyEscape}=1

    exec ${lib.getExe claudeWrapped} "$@"
  '';
in
{
  inherit claudeWrapped claudeRcWrapped wrapperBody;
}
