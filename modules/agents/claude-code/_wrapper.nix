/*
  Runtime wrapper for Claude Code.

  The wrapper owns launch-time environment and target selection. It is installed
  into ~/.local/bin/claude from home-manager.nix so it wins over an external
  bun global binary at $XDG_DATA_HOME/bun/bin/claude.
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
  coreutilsTr = lib.getExe' pkgs.coreutils "tr";

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
      if secret_value="$(${coreutilsTr} -d '\r\n' < "$secret_path")" && [ -n "$secret_value" ]; then
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

    ${greptileEnv}
    ${targetScript}

    if [ ! -x "$target" ]; then
      echo "claude-wrapper: ERROR: Claude Code binary not found or not executable at $target" >&2
      exit 127
    fi

    exec "$target" "$@"
  '';

  claudeWrapperScript = pkgs.writeShellScript "claude" wrapperBody;
  claudeWrapped = pkgs.writeShellScriptBin "claude" wrapperBody;
in
{
  inherit
    claudeWrapped
    claudeWrapperScript
    ;
}
