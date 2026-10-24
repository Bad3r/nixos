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
  scratchDir,
  magnitudeClient ? null,
}:
let
  rmShim = import ../_rm-shim.nix { inherit lib pkgs; };

  # _env.nix vars minus launchOnly, rendered as shell exports.
  claudeEnv = import ./_env.nix;
  envExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") (
      builtins.removeAttrs claudeEnv.vars claudeEnv.launchOnly
    )
  );
  # Guarded rather than unconditional: claude-rc sets the escape variable to
  # keep DISABLE_TELEMETRY out of the launch, which is what re-enables the
  # GrowthBook evaluation Remote Control requires.
  launchOnlyBlock = lib.optionalString (claudeEnv.launchOnly != [ ]) ''
    if [ -z "''${${claudeEnv.launchOnlyEscape}:-}" ]; then
    ${lib.concatMapStringsSep "\n" (
      name: "  export ${name}=${lib.escapeShellArg claudeEnv.vars.${name}}"
    ) claudeEnv.launchOnly}
    else
      unset ${lib.concatStringsSep " " claudeEnv.launchOnly}
    fi
  '';

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
    ${launchOnlyBlock}

    # Shared scratch root for agent temp files.
    tmpDir=${lib.escapeShellArg scratchDir}
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
  # opt-outs for feature flags. Every other _env.nix var still applies.
  claudeRcWrapped = pkgs.writeShellScriptBin "claude-rc" ''
    set -euo pipefail

    unset ${lib.concatStringsSep " " claudeEnv.launchOnly} DO_NOT_TRACK
    unset DISABLE_GROWTHBOOK
    export ${claudeEnv.launchOnlyEscape}=1

    exec ${lib.getExe claudeWrapped} "$@"
  '';

  # Points every model slot at one Magnitude model. The launcher and settings.json
  # pin the haiku and subagent slots to cloud models, and only `--settings` env
  # outranks both; Magnitude holds one model at a time, so mixed slots reload it.
  claudeLocalWrapped = pkgs.writeShellApplication {
    name = "claude-local";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      model=''${CLAUDE_LOCAL_MODEL:-${lib.escapeShellArg magnitudeClient.model}}
      settings=$(jq -cn \
        --arg model "$model" \
        --arg url ${lib.escapeShellArg "${magnitudeClient.endpoint}/inference/anthropic"} \
        --arg context ${toString magnitudeClient.contextWindow} '
          {
            model: $model,
            env: {
              ANTHROPIC_BASE_URL: $url,
              ANTHROPIC_DEFAULT_HAIKU_MODEL: $model,
              ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME: $model,
              ANTHROPIC_DEFAULT_SONNET_MODEL: $model,
              ANTHROPIC_DEFAULT_OPUS_MODEL: $model,
              CLAUDE_CODE_SUBAGENT_MODEL: $model,
              CLAUDE_CODE_MAX_CONTEXT_TOKENS: $context
            }
          }
        ')
      ${
        if magnitudeClient.apiKeyFile == null then
          "ANTHROPIC_AUTH_TOKEN=magnitude-local"
        else
          "ANTHROPIC_AUTH_TOKEN=$(<${lib.escapeShellArg magnitudeClient.apiKeyFile})"
      }
      export ANTHROPIC_AUTH_TOKEN

      exec ${lib.getExe claudeWrapped} --settings "$settings" "$@"
    '';
  };
in
{
  inherit
    claudeWrapped
    claudeRcWrapped
    claudeLocalWrapped
    wrapperBody
    ;
}
