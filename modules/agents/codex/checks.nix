{
  config,
  lib,
  inputs,
  ...
}:
let
  agents = config.flake.lib.agents;
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      codexPkg = inputs.llm-agents.packages.${system}.codex;
      # Include app-backed MCP entries in parser validation without building their services.
      osConfig.programs.sbx.extended = {
        enable = true;
        finalPackage = pkgs.emptyDirectory;
        limits.maxTtl = 1;
      };
      codexNotify = import ./_notify.nix {
        inherit pkgs;
        icon = pkgs.emptyFile;
      };
      mkSettings =
        telemetry:
        import ./_settings.nix {
          inherit telemetry;
          inherit
            agents
            lib
            osConfig
            pkgs
            ;
          homeDir = "/home/codex-config-check";
          inherit codexNotify;
        };
      execPolicy = import ./_exec-policy.nix {
        inherit lib pkgs;
        scratchDir = "/tmp/codex-config-check-scratch";
      };
      mkRuntime =
        settings:
        import ./_wrapper.nix {
          inherit lib pkgs codexPkg;
          scratchDir = "/tmp/codex-config-check-scratch";
          inherit (settings) baseSettings nixProjectSettings;
          inherit (execPolicy) codexBashWrapper;
          homeDir = "/home/codex-config-check";
          configDir = "/home/codex-config-check/.config/codex";
        };
      telemetry = import ./_telemetry.nix {
        inherit pkgs;
        enabled = true;
      };
      disabledSettings = mkSettings (
        import ./_telemetry.nix {
          inherit pkgs;
          enabled = false;
        }
      );
      mkConfigCheck =
        name: settings:
        let
          runtime = mkRuntime settings;
        in
        pkgs.runCommandLocal name
          {
            nativeBuildInputs = [ pkgs.uv ];
            UV_PYTHON = lib.getExe pkgs.python314;
            UV_NO_MANAGED_PYTHON = "1";
            UV_OFFLINE = "1";
            UV_NO_CACHE = "1";
            passthru.runtimeCheck = true;
          }
          ''
            mkdir -p "$PWD/generated"
            ln -s ${runtime.baseConfigFile} "$PWD/generated/config.base.toml"
            ln -s ${runtime.nixProjectsFile} "$PWD/generated/projects.nix.toml"
            uv run --no-project ${./_config-check.py} \
              ${lib.getExe codexPkg} ${lib.getExe runtime.codexWrapped}
            touch "$out"
          '';
      telemetryCheck = pkgs.replaceVars ./_telemetry-check.py {
        collector = lib.getExe pkgs.opentelemetry-collector-contrib;
        config = telemetry.collectorConfigFile;
      };
    in
    {
      checks = {
        "codex/telemetry-collector" =
          pkgs.runCommandLocal "codex-telemetry-collector-check" { passthru.runtimeCheck = true; }
            ''
              STATE_DIRECTORY="$TMPDIR" ${lib.getExe pkgs.opentelemetry-collector-contrib} validate \
                --config=${telemetry.collectorConfigFile}
              ${lib.getExe pkgs.python314} ${telemetryCheck}
              touch "$out"
            '';

        "codex/notify" =
          pkgs.runCommandLocal "codex-notify-check"
            {
              passthru.runtimeCheck = true;
              nativeBuildInputs = [ pkgs.jq ];
            }
            ''
              expect() {
                local got
                got=$(jq -r -f ${codexNotify.filter} <<<"$1")
                if [ "$got" != "$2" ]; then
                  printf 'FAIL: %s\nexpected: %s\ngot: %s\n' "$1" "$2" "$got" >&2
                  exit 1
                fi
              }
              grep -qF ${lib.escapeShellArg codexNotify.titlePrefix} ${codexPkg.src}/codex-rs/tui/src/app/thread_title.rs || {
                echo "FAIL: codex ${codexPkg.version} thread_title.rs lacks the notify filter's title prefix" >&2
                exit 1
              }
              expect ${
                lib.escapeShellArg (
                  builtins.toJSON {
                    type = "agent-turn-complete";
                    input-messages = [ "${codexNotify.titlePrefix} for: fix it" ];
                    last-assistant-message = "Fix CI";
                  }
                )
              } ""
              expect '{"type":"agent-turn-complete","last-assistant-message":"a < b & c","cwd":"/w/<x>&y/"}' \
                "summary='Codex · <x>&y' body='a &lt; b &amp; c'"
              expect '{"type":"agent-turn-complete","last-assistant-message":" \n","cwd":"/w/r"}' "summary='Codex · r' body='Turn complete'"
              expect '{"type":"approval-requested","cwd":"/w/r"}' "summary='Codex' body='Event: approval-requested'"
              long=$(printf '%0250d' 0 | tr 0 x)
              clipped="''${long:0:199}…"
              expect "{\"type\":\"agent-turn-complete\",\"last-assistant-message\":\"$long\"}" "summary='Codex' body='$clipped'"
              touch "$out"
            '';

        "codex/config" = mkConfigCheck "codex-config-check" (mkSettings telemetry);

        "codex/config-telemetry-disabled" =
          let
            settings = disabledSettings.baseSettings;
          in
          assert lib.all (key: settings.otel.${key} == "none") [
            "exporter"
            "trace_exporter"
            "metrics_exporter"
          ];
          assert settings.features.runtime_metrics == false;
          assert settings.analytics.enabled == false;
          assert settings.feedback.enabled == false;
          assert lib.all (key: settings.otel.${key} == false) [
            "log_user_prompt"
            "log_agent_responses"
            "log_guardian_assessments"
          ];
          mkConfigCheck "codex-config-telemetry-disabled-check" disabledSettings;
      };
    };
}
