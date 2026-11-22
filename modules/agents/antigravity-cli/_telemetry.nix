# Shared telemetry, analytics, and background update controls for Antigravity CLI and Hub.
let
  # Google Cloud / Clearcut telemetry and analytics flag for `language_server`
  # and root / `acp` invocations of `agy`.
  languageServerFlags = [ "--disable_telemetry" ];

  # Disable implicit config watch, usage statistics, and npm update checks in
  # `chrome-devtools-mcp` child processes spawned by Antigravity.
  sharedEnv = {
    CHROME_DEVTOOLS_MCP_NO_CONFIG_DISCOVERY = "1";
    CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS = "1";
    CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS = "1";
  };

  # Nix manages CLI updates, so disable 15-minute `--bg-updater` checks.
  cliEnv = sharedEnv // {
    AGY_CLI_DISABLE_AUTO_UPDATE = "1";
  };

  # Hub stores UI settings as strings in app_storage.json; `SettingsService`
  # compares `items.autoCheckForUpdates === "true"`.
  hubStorage = {
    autoCheckForUpdates = "false";
  };

  # `agy` subcommands that parse isolated FlagSets and reject `--disable_telemetry`.
  nonTelemetrySubcommands = [
    "agent"
    "agents"
    "changelog"
    "help"
    "install"
    "mcp"
    "mic-serve"
    "models"
    "plugin"
    "plugins"
    "remote-control"
    "update"
  ];

  # Wrap `agy` with the controlled shell, disabled telemetry/auto-updates, and
  # per-subcommand `--disable_telemetry` placement.
  wrapAgy =
    {
      lib,
      pkgs,
      package,
      shell,
      scratchDir,
    }:
    let
      exportEnv = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") cliEnv
      );
      nonTelemetryCases = lib.concatMapStringsSep " | " lib.escapeShellArg nonTelemetrySubcommands;
    in
    pkgs.symlinkJoin (
      {
        name = "antigravity-cli-${package.version or "custom"}";
        paths = [ package ];
        postBuild = ''
          rm -f "$out/bin/agy"
          mkdir -p "$out/bin"
          cat > "$out/bin/agy" <<'WRAPPER_EOF'
          #!${pkgs.runtimeShell}
          set -euo pipefail
          export PATH="${shell.antigravityBashWrapper}/bin:${shell.rmShim}/bin''${PATH:+:$PATH}"
          ${exportEnv}
          if [ -z "''${TMPDIR:-}" ] && [ -d ${lib.escapeShellArg scratchDir} ] && [ -w ${lib.escapeShellArg scratchDir} ]; then
            export TMPDIR=${lib.escapeShellArg scratchDir}
          fi
          case "''${1:-}" in
            "acp")
              shift
              set -- acp --disable_telemetry "$@"
              ;;
            ${nonTelemetryCases})
              ;;
            *)
              set -- --disable_telemetry "$@"
              ;;
          esac
          exec -a "$0" ${lib.escapeShellArg "${package}/bin/agy"} "$@"
          WRAPPER_EOF
          chmod +x "$out/bin/agy"
        '';
      }
      // lib.optionalAttrs (package ? version) { inherit (package) version; }
      // {
        meta = (package.meta or { }) // {
          mainProgram = "agy";
        };
      }
    );
in
{
  inherit
    cliEnv
    hubStorage
    languageServerFlags
    nonTelemetrySubcommands
    sharedEnv
    wrapAgy
    ;
}
