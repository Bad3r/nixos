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
  greptilePluginRequested,
  greptileApiKeyPath,
}:
let
  rmShim = import ../_rm-shim.nix { inherit lib pkgs; };

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

    if [ "$#" -ge 2 ] && { [ "$1" = "-c" ] || [ "$1" = "-lc" ]; }; then
      shellFlag="$1"
      wrappedCommand="$2"
      shift 2

      export CLAUDE_WRAPPED_COMMAND="$wrappedCommand"
      exec "$realBash" "$shellFlag" '
        # Load direnv as an interactive shell would.
        if direnvExports="$("'"$direnvBin"'" export bash 2>/dev/null)"; then
          eval "$direnvExports"
        fi
        rm() {
          "'"$rmShimPath"'" "$@"
        }
        eval "$CLAUDE_WRAPPED_COMMAND"
      ' "$@"
    fi

    exec "$realBash" "$@"
  '';

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

  greptileEnv = lib.optionalString greptilePluginRequested ''
    secret_path="''${GREPTILE_API_KEY_FILE:-${greptileApiKeyPath}}"
    if [ -r "$secret_path" ] && [ -s "$secret_path" ]; then
      secret_value=$(< "$secret_path")
      secret_value="''${secret_value//[$'\r\n']/}"
      if [ -n "$secret_value" ]; then
        export GREPTILE_API_KEY="$secret_value"
      fi
    fi
  '';

  wrapperBody = ''
    set -euo pipefail

    export DISABLE_AUTOUPDATER=1
    export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
    export DISABLE_NON_ESSENTIAL_MODEL_CALLS=1
    export DISABLE_TELEMETRY=1
    export DISABLE_INSTALLATION_CHECKS=1
    export CLAUDE_CODE_ENABLE_TELEMETRY=0
    export DISABLE_ERROR_REPORTING=1
    export CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1
    export BASH_DEFAULT_TIMEOUT_MS=240000
    export BASH_MAX_TIMEOUT_MS=4800000
    export BASH_MAX_OUTPUT_LENGTH=1024
    export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=0
    export CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL=1
    export DISABLE_BUG_COMMAND=1
    export USE_BUILTIN_RIPGREP=0

    # Shared scratch root for agent temp files.
    tmpDir="/tmp/agents"
    mkdir -p "$tmpDir"
    export TMPDIR="$tmpDir"

    # Covers Claude itself and any fallback shell (if CLAUDE_CODE_SHELL is
    # rejected); the controlled bash re-asserts the same prepend.
    export PATH=${rmShim}/bin''${PATH:+:$PATH}

    export CLAUDE_CODE_SHELL=${lib.escapeShellArg "${claudeBashWrapper}/bin/bash"}

    ${greptileEnv}
    ${targetScript}

    if [ ! -x "$target" ]; then
      echo "claude-wrapper: ERROR: Claude Code binary not found or not executable at $target" >&2
      exit 127
    fi

    exec "$target" "$@"
  '';

  claudeWrapped = pkgs.writeShellScriptBin "claude" wrapperBody;
in
{
  inherit claudeWrapped;
}
