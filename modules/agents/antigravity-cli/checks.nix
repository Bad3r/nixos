{ config, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      scratchDir = config.flake.lib.agents.scratchDir;
      json = name: value: pkgs.writeText name (builtins.toJSON value);

      activation = import ./_activation.nix {
        inherit lib pkgs;
        mcpServersFile = null;
        hooksFile = null;
        pluginsFile = null;
        permissionsFile = null;
        stateFile = null;
      };
      inherit (activation) applyConfig;

      shell = import ./_shell.nix {
        inherit lib pkgs;
        scratchDir = "/nonexistent/agy-shell-check-missing";
      };

      mcpTemplate = json "mcp-template.json" {
        sbx = {
          command = "/nix/store/sbx/bin/sbx-mcp";
          args = [ ];
        };
        deepwiki = {
          serverUrl = "https://mcp.deepwiki.com/mcp";
        };
      };
      hooksTemplate = json "hooks-template.json" {
        herdr-antigravity-session = {
          PreInvocation = [
            {
              type = "command";
              command = "/nix/store/herdr/bin/herdr-antigravity-session";
              timeout = 10;
            }
          ];
        };
        scratch-guard = {
          PreToolUse = [
            {
              matcher = "write_file|edit_file|run_command";
              hooks = [
                {
                  type = "command";
                  command = "/nix/store/guard/bin/agent-scratch-guard";
                  timeout = 10;
                }
              ];
            }
          ];
        };
      };
      pluginsTemplate = json "plugins-template.json" {
        cloudflare = true;
        egm = false;
        swarm = true;
      };
      permissionsTemplate = json "permissions-template.json" {
        allow = [ "command(git)" ];
        ask = [ "command(git push --force)" ];
        deny = [ "command(/bin/rm)" ];
      };
      cliSettingsTemplate = json "cli-settings-template.json" {
        agentMode = "auto";
        toolPermission = "proceed-in-sandbox";
        permissions = {
          allow = [ "command(git)" ];
          ask = [ "command(git push --force)" ];
          deny = [ "command(/bin/rm)" ];
        };
      };
      stateTemplate = json "state-template.json" {
        version = 1;
        mcpServers = [
          "deepwiki"
          "sbx"
        ];
        hooks = [
          "herdr-antigravity-session"
          "scratch-guard"
        ];
        plugins = [
          "cloudflare"
          "egm"
          "swarm"
        ];
        cliSettings = [
          "agentMode"
          "permissions"
          "toolPermission"
        ];
      };

      reducedMcpTemplate = json "mcp-reduced.json" {
        sbx = {
          command = "/nix/store/sbx/bin/sbx-mcp";
          args = [ ];
        };
      };
      reducedHooksTemplate = json "hooks-reduced.json" {
        scratch-guard = {
          PreToolUse = [
            {
              matcher = "write_file|edit_file|run_command";
              hooks = [
                {
                  type = "command";
                  command = "/nix/store/guard/bin/agent-scratch-guard";
                  timeout = 10;
                }
              ];
            }
          ];
        };
      };
      reducedPluginsTemplate = json "plugins-reduced.json" {
        cloudflare = true;
      };
      reducedCliTemplate = json "cli-reduced.json" {
        agentMode = "auto";
      };
      reducedStateTemplate = json "state-reduced.json" {
        version = 1;
        mcpServers = [ "sbx" ];
        hooks = [ "scratch-guard" ];
        plugins = [ "cloudflare" ];
        cliSettings = [ "agentMode" ];
      };

      liveMcp = json "live-mcp.json" {
        mcpServers = {
          "google-developer-knowledge_google-developer-knowledge".disabled = true;
          "migrated-settings_openaiDeveloperDocs".disabled = true;
          custom-local.command = "keep-me";
        };
      };
      liveHooks = json "live-hooks.json" {
        herdr.PreInvocation = [
          {
            type = "command";
            command = "bash '/home/vx/.gemini/config/hooks/herdr-agent-state.sh' session";
            timeout = 10;
          }
        ];
        user-custom.PreInvocation = [
          {
            type = "command";
            command = "echo custom";
          }
        ];
      };
      liveConfig = json "live-config.json" {
        plugins = {
          cloudflare.installedFrom = {
            id = "antigravity-plugins-partners/plugin/cloudflare";
            marketplace = "antigravity-plugins-partners";
            version = "1.0.4";
          };
          migrated-settings = {
            enabled = true;
          };
        };
        sidecars."swarm/swarm_board".projectId = "6d5a6539-3b2c-4eee-8a29-dfbef460159a";
        userSettings = {
          customThemeSeedsDark.primary = "#3994bc";
          globalPermissionGrants.allow = [ "stale_rule" ];
        };
      };
      liveCliSettings = json "live-cli-settings.json" {
        agentMode = "accept-edits";
        toolPermission = "always-proceed";
        model = "Orchestrator (Neon)";
        orchestrator.planner = "Gemini 4 Carbon (High)";
        trustedWorkspaces = [ "/home/vx/nixos" ];
      };
    in
    {
      checks = {
        "antigravity-cli/activation-merge" =
          pkgs.runCommandLocal "antigravity-cli-activation-merge"
            {
              passthru.runtimeCheck = true;
              nativeBuildInputs = [ pkgs.jq ];
            }
            ''
              set -euo pipefail
              apply() {
                ${lib.getExe applyConfig} \
                  ${mcpTemplate} \
                  ${hooksTemplate} \
                  ${pluginsTemplate} \
                  ${permissionsTemplate} \
                  ${stateTemplate} \
                  ${cliSettingsTemplate}
              }
              check() {
                local file=$1 query=$2 expected=$3 actual
                actual=$(jq -cS "$query" "$file")
                if [ "$actual" != "$expected" ]; then
                  echo "FAIL: $file: $query: expected $expected, got $actual" >&2
                  exit 1
                fi
              }
              seed() {
                export HOME=$PWD/$1
                mkdir -p "$HOME/.gemini/config/plugins/migrated-settings" \
                  "$HOME/.gemini/antigravity/plugin_data/migrated-settings" \
                  "$HOME/.gemini/antigravity-cli/plugin_data/migrated-settings"
                touch "$HOME/.gemini/config/.migrated" "$HOME/.gemini/config/mcp_config.json.backup"
              }
              put() {
                mkdir -p "$(dirname "$2")"
                install -m 600 "$1" "$2"
              }

              # 1. First run cleans migrated-settings artifacts, replaces legacy rules, preserves provenance and runtime prefs.
              seed initial
              put ${liveMcp} "$HOME/.gemini/config/mcp_config.json"
              put ${liveHooks} "$HOME/.gemini/config/hooks.json"
              put ${liveConfig} "$HOME/.gemini/config/config.json"
              put ${liveCliSettings} "$HOME/.gemini/antigravity-cli/settings.json"
              apply

              [ ! -e "$HOME/.gemini/config/plugins/migrated-settings" ]
              [ ! -e "$HOME/.gemini/antigravity/plugin_data/migrated-settings" ]
              [ ! -e "$HOME/.gemini/antigravity-cli/plugin_data/migrated-settings" ]
              [ ! -e "$HOME/.gemini/config/.migrated" ]
              [ ! -e "$HOME/.gemini/config/mcp_config.json.backup" ]

              mcp="$HOME/.gemini/config/mcp_config.json"
              hooks="$HOME/.gemini/config/hooks.json"
              cfg="$HOME/.gemini/config/config.json"
              cli="$HOME/.gemini/antigravity-cli/settings.json"
              state="$HOME/.gemini/config/.nix-managed.json"

              check "$mcp" '.mcpServers | has("migrated-settings_openaiDeveloperDocs")' false
              check "$mcp" '.mcpServers["google-developer-knowledge_google-developer-knowledge"].disabled' true
              check "$mcp" '.mcpServers["custom-local"].command' '"keep-me"'
              check "$mcp" '.mcpServers.deepwiki.serverUrl' '"https://mcp.deepwiki.com/mcp"'

              check "$hooks" 'has("herdr")' false
              check "$hooks" 'has("herdr-antigravity-session")' true
              check "$hooks" 'has("scratch-guard")' true
              check "$hooks" '.["user-custom"].PreInvocation[0].command' '"echo custom"'

              check "$cfg" '.plugins | has("migrated-settings")' false
              check "$cfg" '.plugins.cloudflare.installedFrom.marketplace' '"antigravity-plugins-partners"'
              check "$cfg" '.plugins.cloudflare.enabled' true
              check "$cfg" '.plugins.egm.enabled' false
              check "$cfg" '.plugins.swarm.enabled' true
              check "$cfg" '.sidecars["swarm/swarm_board"].projectId' '"6d5a6539-3b2c-4eee-8a29-dfbef460159a"'
              check "$cfg" '.userSettings.customThemeSeedsDark.primary' '"#3994bc"'
              check "$cfg" '.userSettings.globalPermissionGrants.allow' '["command(git)"]'

              check "$cli" '.agentMode' '"auto"'
              check "$cli" '.toolPermission' '"proceed-in-sandbox"'
              check "$cli" '.model' '"Orchestrator (Neon)"'
              check "$cli" '.orchestrator.planner' '"Gemini 4 Carbon (High)"'
              check "$cli" '.trustedWorkspaces' '["/home/vx/nixos"]'
              cmp ${stateTemplate} "$state"

              for f in "$mcp" "$hooks" "$cfg" "$cli" "$state"; do
                [ "$(stat -c %a "$f")" = "600" ]
              done

              # 2. Second run is byte-for-byte idempotent, and a user-created mcp_config.json.backup without
              # migration markers is preserved.
              cp "$mcp" mcp.first
              cp "$hooks" hooks.first
              cp "$cfg" cfg.first
              cp "$cli" cli.first
              touch "$HOME/.gemini/config/mcp_config.json.backup"
              apply
              cmp mcp.first "$mcp"
              cmp hooks.first "$hooks"
              cmp cfg.first "$cfg"
              cmp cli.first "$cli"
              [ -e "$HOME/.gemini/config/mcp_config.json.backup" ]

              # 2b. Mixed .herdr preserves custom entries while stripping the legacy herdr-agent-state.sh hook.
              jq --arg legacyCmd "bash '/home/vx/.gemini/config/hooks/herdr-agent-state.sh' session" '.herdr = {
                PreInvocation: [
                  { type: "command", command: $legacyCmd, timeout: 10 },
                  { type: "command", command: "echo keep-herdr-custom" }
                ],
                PostToolUse: [
                  { matcher: "run_command", hooks: [ { type: "command", command: "echo keep-post" } ] }
                ]
              }' "$hooks" >"$hooks.mixed"
              mv "$hooks.mixed" "$hooks"
              chmod 0600 "$hooks"
              apply
              check "$hooks" '.herdr.PreInvocation | length' 1
              check "$hooks" '.herdr.PreInvocation[0].command' '"echo keep-herdr-custom"'
              check "$hooks" '.herdr.PostToolUse[0].matcher' '"run_command"'

              # 3. Dropping entries removes only Nix-managed keys and keeps installedFrom on plugins.
              ${lib.getExe applyConfig} \
                ${reducedMcpTemplate} \
                ${reducedHooksTemplate} \
                ${reducedPluginsTemplate} \
                ${permissionsTemplate} \
                ${reducedStateTemplate} \
                ${reducedCliTemplate}
              check "$mcp" '.mcpServers | has("deepwiki")' false
              check "$mcp" '.mcpServers | has("custom-local")' true
              check "$hooks" 'has("herdr-antigravity-session")' false
              check "$hooks" 'has("user-custom")' true
              check "$cfg" '.plugins | has("swarm")' false
              check "$cfg" '.plugins | has("egm")' false
              check "$cfg" '.plugins.cloudflare.enabled' true
              check "$cli" 'has("toolPermission")' false
              check "$cli" '.model' '"Orchestrator (Neon)"'

              # 4. Hub-only mode omits settings.json creation, and CLI -> Hub-only -> CLI retains prior cliSettings ownership.
              seed hub-only
              ${lib.getExe applyConfig} \
                ${mcpTemplate} \
                ${hooksTemplate} \
                ${pluginsTemplate} \
                ${permissionsTemplate} \
                ${stateTemplate} \
                ""
              [ ! -e "$HOME/.gemini/antigravity-cli/settings.json" ]
              check "$HOME/.gemini/config/config.json" '.plugins.cloudflare.enabled' true

              seed cli-hub-cli
              ${lib.getExe applyConfig} \
                ${mcpTemplate} \
                ${hooksTemplate} \
                ${pluginsTemplate} \
                ${permissionsTemplate} \
                ${stateTemplate} \
                ${cliSettingsTemplate}
              ${lib.getExe applyConfig} \
                ${mcpTemplate} \
                ${hooksTemplate} \
                ${pluginsTemplate} \
                ${permissionsTemplate} \
                ${reducedStateTemplate} \
                ""
              check "$HOME/.gemini/config/.nix-managed.json" '.cliSettings' '["agentMode","permissions","toolPermission"]'
              ${lib.getExe applyConfig} \
                ${reducedMcpTemplate} \
                ${reducedHooksTemplate} \
                ${reducedPluginsTemplate} \
                ${permissionsTemplate} \
                ${reducedStateTemplate} \
                ${reducedCliTemplate}
              check "$HOME/.gemini/antigravity-cli/settings.json" 'has("toolPermission")' false
              check "$HOME/.gemini/antigravity-cli/settings.json" '.agentMode' '"auto"'

              # 5. Corrupt .nix-managed.json fails --check and apply before touching live files or cleaning migrated-settings.
              seed corrupt-state
              put ${liveConfig} "$HOME/.gemini/config/config.json"
              printf 'not json' >"$HOME/.gemini/config/.nix-managed.json"
              if ${lib.getExe applyConfig} --check "" "" "" "" "" ${cliSettingsTemplate}; then
                echo "FAIL: --check accepted corrupt .nix-managed.json" >&2
                exit 1
              fi
              if apply; then
                echo "FAIL: corrupt .nix-managed.json accepted" >&2
                exit 1
              fi
              cmp ${liveConfig} "$HOME/.gemini/config/config.json"
              [ -d "$HOME/.gemini/config/plugins/migrated-settings" ]

              # 6. Non-object live file fails --check and apply before replacing earlier staged files or deleting migrated-settings.
              seed non-object-live
              put ${liveMcp} "$HOME/.gemini/config/mcp_config.json"
              printf '[]' >"$HOME/.gemini/config/config.json"
              if ${lib.getExe applyConfig} --check "" "" "" "" "" ${cliSettingsTemplate}; then
                echo "FAIL: --check accepted array config.json" >&2
                exit 1
              fi
              if apply; then
                echo "FAIL: array config.json accepted" >&2
                exit 1
              fi
              cmp ${liveMcp} "$HOME/.gemini/config/mcp_config.json"
              [ "$(cat "$HOME/.gemini/config/config.json")" = "[]" ]
              [ -d "$HOME/.gemini/config/plugins/migrated-settings" ]

              echo "ok: antigravity-apply-config contract" >$out
            '';

        "antigravity-cli/shell-wrapper" =
          pkgs.runCommandLocal "antigravity-cli-shell-wrapper" { passthru.runtimeCheck = true; }
            ''
              set -euo pipefail
              export HOME="$TMPDIR/home"
              export XDG_DATA_HOME="$TMPDIR/xdg"
              mkdir -p "$HOME" "$XDG_DATA_HOME"

              # 1. Nested PATH strips the wrapper dir (even with trailing slash) while keeping rm shim first,
              # and empty PATH still runs.
              got_path="$(PATH="${shell.antigravityBashWrapper}/bin/:${shell.rmShim}/bin:${pkgs.coreutils}/bin" \
                ${shell.antigravityBashWrapper}/bin/bash -c 'printf "%s" "$PATH"')"
              empty_path_out="$(PATH="" ${shell.antigravityBashWrapper}/bin/bash -c 'printf ok')"
              if [ "$empty_path_out" != "ok" ]; then
                echo "FAIL: empty PATH invocation returned '$empty_path_out'" >&2
                exit 1
              fi
              case ":$got_path:" in
                *":${shell.antigravityBashWrapper}/bin:"*)
                  echo "FAIL: wrapper dir remained in nested PATH: $got_path" >&2
                  exit 1
                  ;;
              esac
              case "$got_path" in
                "${shell.rmShim}/bin:"* | "${shell.rmShim}/bin") ;;
                *)
                  echo "FAIL: rm shim not first on PATH: $got_path" >&2
                  exit 1
                  ;;
              esac

              # 1b. Non--c long/multi-arg options work, -o errexit -c stays wrapped, and wrapper env does not leak.
              norc_out="$(PATH="${shell.antigravityBashWrapper}/bin:${pkgs.coreutils}/bin" \
                ${shell.antigravityBashWrapper}/bin/bash -norc /dev/stdin <<<'printf norc-ok')"
              if [ "$norc_out" != "norc-ok" ]; then
                echo "FAIL: -norc stdin returned '$norc_out'" >&2
                exit 1
              fi
              errexit_rm="$(PATH="${shell.antigravityBashWrapper}/bin:${shell.rmShim}/bin:${pkgs.coreutils}/bin" \
                ${shell.antigravityBashWrapper}/bin/bash -o errexit -c 'type -t rm')"
              if [ "$errexit_rm" != "function" ]; then
                echo "FAIL: -o errexit -c type -t rm returned '$errexit_rm'" >&2
                exit 1
              fi
              dash_arg_out="$(PATH="${shell.antigravityBashWrapper}/bin:${pkgs.coreutils}/bin" \
                ${shell.antigravityBashWrapper}/bin/bash -c 'printf "%s:%s:%s" "''${ANTIGRAVITY_WRAPPED_COMMAND-clean}" "$0" "$1"' arg0 -foo)"
              if [ "$dash_arg_out" != "clean:arg0:-foo" ]; then
                echo "FAIL: env/arg check returned '$dash_arg_out'" >&2
                exit 1
              fi

              # 2. ANTIGRAVITY_CONVERSATION_ID creates per-session TMPDIR under scratchDir.
              writable_scratch="$TMPDIR/writable-scratch"
              mkdir -p "$writable_scratch"
              fallback_tmp="$(TMPDIR="/nonexistent/scratch" \
                ANTIGRAVITY_CONVERSATION_ID="conv-123" \
                PATH="${shell.antigravityBashWrapper}/bin:${pkgs.coreutils}/bin" \
                ${shell.antigravityBashWrapper}/bin/bash -c 'printf "%s" "$TMPDIR"')"
              if [ "$fallback_tmp" != "/tmp" ]; then
                echo "FAIL: expected /tmp fallback, got '$fallback_tmp'" >&2
                exit 1
              fi

              wrapper_copy="$TMPDIR/bash-wrapper"
              sed "s|/nonexistent/agy-shell-check-missing|$writable_scratch|g" \
                "${shell.antigravityBashWrapper}/bin/bash" >"$wrapper_copy"
              chmod +x "$wrapper_copy"
              session_tmp="$(ANTIGRAVITY_CONVERSATION_ID="conv-123" \
                PATH="$TMPDIR:${pkgs.coreutils}/bin" \
                "$wrapper_copy" -c 'printf "%s" "$TMPDIR"')"
              if [ "$session_tmp" != "$writable_scratch/sessions/conv-123" ] || [ ! -d "$session_tmp" ]; then
                echo "FAIL: expected session TMPDIR under '$writable_scratch/sessions/conv-123', got '$session_tmp'" >&2
                exit 1
              fi

              # 3. Bare rm and command rm route through trash-put instead of unlinking permanently.
              work="$TMPDIR/work"
              mkdir -p "$work"
              touch "$work/a" "$work/b"
              PATH="${shell.antigravityBashWrapper}/bin:${shell.rmShim}/bin:$PATH" \
                ${shell.antigravityBashWrapper}/bin/bash -c "rm '$work/a' && command rm -f '$work/b'"
              if [ -e "$work/a" ] || [ -e "$work/b" ]; then
                echo "FAIL: removed files still present in $work" >&2
                exit 1
              fi
              if [ ! -e "$XDG_DATA_HOME/Trash/files/a" ] || [ ! -e "$XDG_DATA_HOME/Trash/files/b" ]; then
                echo "FAIL: trashed files missing in $XDG_DATA_HOME/Trash/files" >&2
                exit 1
              fi

              # Keep config.flake.lib.agents.scratchDir forced during eval.
              [ -n "${scratchDir}" ]

              echo "ok: antigravity-cli shell wrapper" >$out
            '';
      };
    };
}
