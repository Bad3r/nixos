# Shared telemetry, analytics, and background update controls for Antigravity CLI and Hub.
let
  # `language_server` telemetry/analytics flag (`agy acp` and Hub `language_server`).
  # External root `agy` builds compile out `--disable_telemetry`.
  languageServerFlags = [ "--disable_telemetry" ];

  # Disable implicit config watch, usage statistics, npm update checks in
  # `chrome-devtools-mcp` child processes, and telemetry in `modern-web-guidance`.
  sharedEnv = {
    CHROME_DEVTOOLS_MCP_NO_CONFIG_DISCOVERY = "1";
    CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS = "1";
    CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS = "1";
    DISABLE_TELEMETRY = "1";
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

  # Known `agy` subcommands pinned against upstream `--help` output.
  knownSubcommands = [
    "acp"
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

  # Wrap `agy` with the controlled shell, disabled auto-updates and MCP checks,
  # and `--disable_telemetry` on `acp` (rejecting falsy overrides before `--`).
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
          if [ "''${1:-}" = "acp" ]; then
            shift
            for arg in "$@"; do
              [ "$arg" = "--" ] && break
              case "$arg" in
                -disable_telemetry=* | --disable_telemetry=* | -disable-telemetry=* | --disable-telemetry=*)
                  val="''${arg#*=}"
                  case "$val" in
                    1 | t | T | TRUE | true | True) ;;
                    *)
                      echo "agy: telemetry is disabled by NixOS configuration and cannot be re-enabled ($arg)" >&2
                      exit 2
                      ;;
                  esac
                  ;;
              esac
            done
            set -- acp --disable_telemetry "$@"
          fi
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
    knownSubcommands
    languageServerFlags
    sharedEnv
    wrapAgy
    ;
}
