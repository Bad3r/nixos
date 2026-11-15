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
      # The variant the llm-agents fork builds and pushes to bad3r-nixos.
      codexPkg = inputs.llm-agents.packages.${system}.codex-voice;
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
      telemetry = import ./_telemetry.nix { inherit pkgs; };
      # Settings for both states of the local telemetry toggle.
      telemetryStates =
        map
          (enabled: {
            name = if enabled then "local telemetry on" else "local telemetry off";
            settings = (mkSettings (import ./_telemetry.nix { inherit pkgs enabled; })).baseSettings;
          })
          [
            true
            false
          ];
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
      configCheck = mkConfigCheck "codex-config-check" (mkSettings telemetry);
      telemetryCheck = pkgs.replaceVars ./_telemetry-check.py {
        collector = lib.getExe pkgs.opentelemetry-collector-contrib;
        config = telemetry.collectorConfigFile;
      };
    in
    {
      checks = {
        # Fails a Codex bump that would send web.run elsewhere or change what the
        # kagi-search-webrun emulator answers (packages/kagi-search/kagi_search/webrun.py).
        "codex/web-run-contract" =
          let
            src = "${codexPkg.src}/codex-rs";
            pinned = {
              "ext/web-search/web_run_description.md" =
                "1f3879b44690eb7aad9ba97351acda16c4d0c26847bcb4af2964d5989404407e";
              "codex-api/src/search.rs" = "393f53fbdedd7882c5416d00fdde166b06d39d5d669f06981c509d35fb79a53b";
            };
            required = {
              "features/src/lib.rs" = ''key: "standalone_web_search"'';
              "core/src/tools/spec_plan.rs" = "let web_search_mode = (!standalone_web_search_available";
            };
          in
          pkgs.runCommandLocal "codex-web-run-contract-check" { passthru.runtimeCheck = true; } ''
            failed=0
            fail() {
              echo "FAIL (codex ${codexPkg.version}): $1" >&2
              failed=1
            }
            # The Bad3r/codex release carries the local-command patch in its source.
            grep -qF CODEX_WEB_RUN_COMMAND ${src}/ext/web-search/src/tool.rs \
              || fail "the codex source does not read CODEX_WEB_RUN_COMMAND, which home.nix sets, so web.run would call OpenAI's alpha/search"
            ${lib.concatStrings (
              lib.mapAttrsToList (file: hash: ''
                got=$(sha256sum ${src}/${file} | cut -d' ' -f1) || got=missing
                [ "$got" = ${hash} ] || fail "${file} changed upstream (sha256 $got); recheck kagi-search-webrun against it, then update the pin"
              '') pinned
            )}
            ${lib.concatStrings (
              lib.mapAttrsToList (file: needle: ''
                grep -qF ${lib.escapeShellArg needle} ${src}/${file} \
                  || fail "${file} no longer has '${needle}'; Codex may now offer OpenAI's hosted web_search beside or instead of web.run"
              '') required
            )}
            [ "$failed" = 0 ]
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

        "codex/config" = configCheck;

        # Fails when the settings would let Codex send telemetry to OpenAI, with
        # local telemetry on or off. Codex defaults analytics events and Statsig
        # metrics (ab.chatgpt.com) on and uploads /feedback reports to OpenAI's
        # Sentry. Not yet covered: with local exporters on, the turn-cost worker
        # posts thread and turn IDs to OpenAI until the Bad3r/codex gate ships.
        "codex/no-openai-telemetry" =
          let
            isLoopback =
              exporter:
              exporter == "none"
              || (
                lib.isAttrs exporter
                && exporter != { }
                && lib.all (
                  kind:
                  lib.elem kind [
                    "otlp-http"
                    "otlp-grpc"
                  ]
                ) (lib.attrNames exporter)
                && lib.all (
                  e: builtins.match "https?://(127\\.0\\.0\\.1|localhost|\\[::1])(:[0-9]+)?(/.*)?" e.endpoint != null
                ) (lib.attrValues exporter)
              );
            leaks =
              { name, settings }:
              map (rule: "${name}: ${rule.why}") (
                lib.filter (rule: rule.leaks) (
                  [
                    {
                      leaks = settings.analytics.enabled or true;
                      why = "analytics.enabled is not false, so analytics events, and Statsig metrics when metrics_exporter is unset, reach OpenAI";
                    }
                    {
                      leaks = settings.feedback.enabled or true;
                      why = "feedback.enabled is not false, so /feedback uploads to OpenAI's Sentry";
                    }
                    {
                      leaks = settings.features.guardianv2_decisions_comparison or true;
                      why = "features.guardianv2_decisions_comparison is not false, so Guardian evidence goes to api.openai.com";
                    }
                  ]
                  # Codex reads an unset metrics_exporter as Statsig.
                  ++
                    map
                      (key: {
                        leaks = !isLoopback (settings.otel.${key} or null);
                        why = "otel.${key} is unset or not a loopback collector";
                      })
                      [
                        "exporter"
                        "trace_exporter"
                        "metrics_exporter"
                      ]
                )
              );
            problems = lib.concatMap leaks telemetryStates;
            src = "${codexPkg.src}/codex-rs";
            # Every non-test source file that names an OpenAI telemetry endpoint.
            endpointPattern = "ab\\.chatgpt\\.com|analytics-events|sentry\\.io|turn-costs|thread-estimates|/v1/decisions";
            endpointFiles = [
              "analytics/src/client.rs"
              "app-server/src/turn_cost_worker.rs"
              "backend-client/src/client/chatgpt_turn_cost.rs"
              "backend-client/src/client/turn_usage.rs"
              "ext/guardian-v2/src/async_scorer/decisions.rs"
              "ext/guardian-v2/src/async_scorer/startup.rs"
              "feedback/src/lib.rs"
              "otel/src/config.rs"
            ];
          in
          if problems != [ ] then
            throw "codex/no-openai-telemetry:\n${lib.concatStringsSep "\n" problems}"
          else
            pkgs.runCommandLocal "codex-no-openai-telemetry-check" { passthru.runtimeCheck = true; } ''
              failed=0
              fail() {
                echo "FAIL (codex ${codexPkg.version}): $1" >&2
                failed=1
              }
              grep -qF '(analytics_enabled != Some(false)).then(' ${src}/analytics/src/client.rs \
                || fail "analytics/src/client.rs no longer gates analytics events on analytics.enabled"
              found=$(cd ${src} && grep -rlE --include='*.rs' ${lib.escapeShellArg endpointPattern} . \
                | sed 's|^\./||' | grep -vE '(^|/)tests?(/|\.rs$)|_tests?\.rs$' | LC_ALL=C sort || true)
              [ "$found" = ${lib.escapeShellArg (lib.concatStringsSep "\n" (lib.sort lib.lessThan endpointFiles))} ] \
                || fail "the files naming OpenAI telemetry endpoints changed; audit what each sends and which setting stops it, then update endpointFiles. Found: $(tr "\n" " " <<<"$found")"
              [ "$failed" = 0 ]
              touch "$out"
            '';
      }
      // lib.optionalAttrs telemetry.enabled {
        "codex/telemetry-collector" =
          pkgs.runCommandLocal "codex-telemetry-collector-check" { passthru.runtimeCheck = true; }
            ''
              STATE_DIRECTORY="$TMPDIR" ${lib.getExe pkgs.opentelemetry-collector-contrib} validate \
                --config=${telemetry.collectorConfigFile}
              ${lib.getExe pkgs.python314} ${telemetryCheck}
              touch "$out"
            '';
      };
    };
}
