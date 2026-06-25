/*
  Runtime wrapper for Claude Code.

  The wrapper owns launch-time environment and target selection. It is installed
  into ~/.local/bin/claude from home-manager.nix, which also prepends
  ~/.local/bin ahead of the bun global bin on home.sessionPath (lib.mkBefore),
  so it wins PATH resolution over an external bun global binary at
  $XDG_DATA_HOME/bun/bin/claude.

  Like the codex wrapper it: corrals temp files under /tmp/agents, and forces a
  controlled bash for the agent's shell tool (rip-backed rm + direnv) instead of
  the user's login shell. Codex injects that bash by overriding the passwd shell
  field through nss_wrapper because it execs the login shell; Claude Code instead
  resolves its shell from CLAUDE_CODE_SHELL (it accepts a path containing
  bash/zsh that is executable), so the wrapper points that variable at the shim
  rather than carrying the nss_wrapper/LD_PRELOAD machinery.
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
  # rm -> rip shim shared with the codex wrapper (modules/agents/_rm-shim.nix).
  rmShim = import ../_rm-shim.nix { inherit lib pkgs; };

  # Controlled bash for Claude's shell tool. Puts the rip-backed `rm` shim first
  # on PATH so bare `rm` stays recoverable for every command and subprocess in
  # any invocation form (-c, -lc, -i, -s, stdin, sourced snapshot), not just the
  # `bash -c` path Claude happens to use today. It also mirrors interactive
  # direnv for `bash -c`/`-lc` commands, then hands off to real bash. This is the
  # codex bash wrapper minus the nss_wrapper LD_PRELOAD restore (Claude never
  # sets that preload). Kept named `bash` so the CLAUDE_CODE_SHELL check accepts
  # it.
  claudeBashWrapper = pkgs.writeShellScriptBin "bash" ''
    set -euo pipefail

    direnvBin=${lib.getExe pkgs.direnv}
    realBash=${lib.getExe pkgs.bashInteractive}
    rmShimPath=${rmShim}/bin/rm

    # The shim dir holds only `rm`, so prepending it shadows nothing else. This
    # is the layer that cannot be bypassed by how the shell is launched; the -c
    # branch below additionally defines an `rm` function as defense in depth.
    export PATH=${rmShim}/bin''${PATH:+:$PATH}

    if [ "$#" -ge 2 ] && { [ "$1" = "-c" ] || [ "$1" = "-lc" ]; }; then
      shellFlag="$1"
      wrappedCommand="$2"
      shift 2

      export CLAUDE_WRAPPED_COMMAND="$wrappedCommand"
      exec "$realBash" "$shellFlag" '
        # Mirror interactive direnv behavior for non-interactive shell commands.
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

    # Corral agent temp files under a shared root, matching the codex wrapper.
    tmpDir="/tmp/agents"
    mkdir -p "$tmpDir"
    export TMPDIR="$tmpDir"

    # Resolve bare `rm` to the rip-backed shim for Claude and every process it
    # spawns, including a fallback shell if CLAUDE_CODE_SHELL is ever rejected,
    # so the safeguard does not depend on the shell launch path. The controlled
    # bash shim re-asserts this on its own PATH as well.
    export PATH=${rmShim}/bin''${PATH:+:$PATH}

    # Force Claude's shell tool onto the controlled bash shim (direnv mirror +
    # rip-backed rm): the CLAUDE_CODE_SHELL analogue of the codex passwd-shell
    # override.
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
