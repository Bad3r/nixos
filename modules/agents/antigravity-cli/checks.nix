{
  config,
  inputs,
  lib,
  metaOwner,
  ...
}:
let
  telemetry = import ./_telemetry.nix;
in
{
  perSystem =
    { pkgs, system, ... }:
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
        hubStorageFile = null;
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
      hubStorageTemplate = json "hub-storage-template.json" telemetry.hubStorage;
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
      reducedHubTemplate = json "hub-reduced.json" { };
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
      liveHubStorage = json "live-hub-storage.json" {
        "enable-wcv-three-layer-stack" = "true";
        autoCheckForUpdates = "true";
        runInBackground = "false";
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
                PATH="/nonexistent" ${lib.getExe applyConfig} \
                  ${mcpTemplate} \
                  ${hooksTemplate} \
                  ${pluginsTemplate} \
                  ${permissionsTemplate} \
                  ${stateTemplate} \
                  ${cliSettingsTemplate} \
                  ${hubStorageTemplate}
              }
              check_state() {
                local actual_file=$1 template_file=$2 hub_target=$3 hub_tpl=''${4:-${hubStorageTemplate}} expected_file
                expected_file=$(mktemp)
                jq -cS --arg target "$hub_target" --slurpfile hub "$hub_tpl" '
                  ($hub[0] | keys) as $keys
                  | . + {
                      hubStorageByTarget: (
                        if ($keys | length) > 0 and $target != "" then
                          { ($target): $keys }
                        else
                          {}
                        end
                      )
                    }
                ' "$template_file" >"$expected_file"
                cmp "$expected_file" "$actual_file"
                rm -f -- "$expected_file"
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
                unset XDG_CONFIG_HOME
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
              put ${liveHubStorage} "$HOME/.config/Antigravity/app_storage.json"
              apply

              [ ! -e "$HOME/.gemini/config/plugins/migrated-settings" ]
              [ ! -e "$HOME/.gemini/antigravity/plugin_data/migrated-settings" ]
              [ ! -e "$HOME/.gemini/antigravity-cli/plugin_data/migrated-settings" ]
              [ -e "$HOME/.gemini/config/.migrated" ]
              [ ! -e "$HOME/.gemini/config/mcp_config.json.backup" ]

              mcp="$HOME/.gemini/config/mcp_config.json"
              hooks="$HOME/.gemini/config/hooks.json"
              cfg="$HOME/.gemini/config/config.json"
              cli="$HOME/.gemini/antigravity-cli/settings.json"
              hub="$HOME/.config/Antigravity/app_storage.json"
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
              check "$hub" '.autoCheckForUpdates' '"false"'
              check "$hub" '.["enable-wcv-three-layer-stack"]' '"true"'
              check "$hub" '.runInBackground' '"false"'
              check_state "$state" ${stateTemplate} "$hub"

              for f in "$mcp" "$hooks" "$cfg" "$cli" "$hub" "$state"; do
                [ "$(stat -c %a "$f")" = "600" ]
              done

              # 2. Second run is byte-for-byte idempotent, preserves inodes when nothing changed, and keeps a
              # user-created mcp_config.json.backup without migration markers.
              cp "$mcp" mcp.first
              cp "$hooks" hooks.first
              cp "$cfg" cfg.first
              cp "$cli" cli.first
              cp "$hub" hub.first
              hub_inode="$(stat -c %i "$hub")"
              cfg_inode="$(stat -c %i "$cfg")"
              state_inode="$(stat -c %i "$state")"
              touch "$HOME/.gemini/config/mcp_config.json.backup"
              apply
              cmp mcp.first "$mcp"
              cmp hooks.first "$hooks"
              cmp cfg.first "$cfg"
              cmp cli.first "$cli"
              cmp hub.first "$hub"
              [ "$(stat -c %i "$hub")" = "$hub_inode" ]
              [ "$(stat -c %i "$cfg")" = "$cfg_inode" ]
              [ "$(stat -c %i "$state")" = "$state_inode" ]
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
                ${reducedCliTemplate} \
                ${reducedHubTemplate}
              check "$mcp" '.mcpServers | has("deepwiki")' false
              check "$mcp" '.mcpServers | has("custom-local")' true
              check "$hooks" 'has("herdr-antigravity-session")' false
              check "$hooks" 'has("user-custom")' true
              check "$cfg" '.plugins | has("swarm")' false
              check "$cfg" '.plugins | has("egm")' false
              check "$cfg" '.plugins.cloudflare.enabled' true
              check "$cli" 'has("toolPermission")' false
              check "$cli" '.model' '"Orchestrator (Neon)"'
              check "$hub" 'has("autoCheckForUpdates")' false
              check "$hub" '.["enable-wcv-three-layer-stack"]' '"true"'
              check "$hub" '.runInBackground' '"false"'

              # 4. Hub-only/CLI-only mode omits disabled app files while retaining ownership across transitions.
              seed hub-only
              export XDG_CONFIG_HOME="$HOME/xdg-custom"
              ${lib.getExe applyConfig} \
                ${mcpTemplate} \
                ${hooksTemplate} \
                ${pluginsTemplate} \
                ${permissionsTemplate} \
                ${stateTemplate} \
                "" \
                ${hubStorageTemplate}
              [ ! -e "$HOME/.gemini/antigravity-cli/settings.json" ]
              check "$HOME/.gemini/config/config.json" '.plugins.cloudflare.enabled' true
              check "$XDG_CONFIG_HOME/Antigravity/app_storage.json" '.autoCheckForUpdates' '"false"'
              [ "$(stat -c %a "$XDG_CONFIG_HOME/Antigravity")" = "700" ]
              [ "$(stat -c %a "$XDG_CONFIG_HOME/Antigravity/app_storage.json")" = "600" ]

              # Explicit xdgConfigHome argument overrides XDG_CONFIG_HOME (matching HM service behavior).
              explicit_xdg="$HOME/xdg-explicit"
              ${lib.getExe applyConfig} \
                ${mcpTemplate} \
                ${hooksTemplate} \
                ${pluginsTemplate} \
                ${permissionsTemplate} \
                ${stateTemplate} \
                "" \
                ${hubStorageTemplate} \
                "$explicit_xdg"
              check "$explicit_xdg/Antigravity/app_storage.json" '.autoCheckForUpdates' '"false"'
              [ "$(stat -c %a "$explicit_xdg/Antigravity")" = "700" ]

              seed cli-hub-cli
              ${lib.getExe applyConfig} \
                ${mcpTemplate} \
                ${hooksTemplate} \
                ${pluginsTemplate} \
                ${permissionsTemplate} \
                ${stateTemplate} \
                ${cliSettingsTemplate} \
                ${hubStorageTemplate}
              ${lib.getExe applyConfig} \
                ${mcpTemplate} \
                ${hooksTemplate} \
                ${pluginsTemplate} \
                ${permissionsTemplate} \
                ${reducedStateTemplate} \
                "" \
                ""
              check "$HOME/.gemini/config/.nix-managed.json" '.cliSettings' '["agentMode","permissions","toolPermission"]'
              check "$HOME/.gemini/config/.nix-managed.json" '.hubStorageByTarget[$ENV.HOME + "/.config/Antigravity/app_storage.json"]' '["autoCheckForUpdates"]'
              ${lib.getExe applyConfig} \
                ${reducedMcpTemplate} \
                ${reducedHooksTemplate} \
                ${reducedPluginsTemplate} \
                ${permissionsTemplate} \
                ${reducedStateTemplate} \
                ${reducedCliTemplate} \
                ${reducedHubTemplate}
              check "$HOME/.gemini/antigravity-cli/settings.json" 'has("toolPermission")' false
              check "$HOME/.gemini/antigravity-cli/settings.json" '.agentMode' '"auto"'
              check "$HOME/.config/Antigravity/app_storage.json" 'has("autoCheckForUpdates")' false

              # 4b. Pre-hubStorageByTarget v1 .nix-managed.json upgrades cleanly.
              seed legacy-state
              put ${stateTemplate} "$HOME/.gemini/config/.nix-managed.json"
              PATH="/nonexistent" ${lib.getExe applyConfig} --check "" "" "" "" "" ${cliSettingsTemplate} ${hubStorageTemplate}
              apply
              check "$HOME/.config/Antigravity/app_storage.json" '.autoCheckForUpdates' '"false"'
              check_state "$HOME/.gemini/config/.nix-managed.json" ${stateTemplate} "$HOME/.config/Antigravity/app_storage.json"

              # 4c. Switching xdgConfigHome preserves unrelated roots and still prunes keys when returning.
              seed xdg-switch
              xdg1="$HOME/xdg1"
              xdg2="$HOME/xdg2"
              ${lib.getExe applyConfig} \
                ${mcpTemplate} \
                ${hooksTemplate} \
                ${pluginsTemplate} \
                ${permissionsTemplate} \
                ${stateTemplate} \
                ${cliSettingsTemplate} \
                ${hubStorageTemplate} \
                "$xdg1"
              put ${liveHubStorage} "$xdg2/Antigravity/app_storage.json"
              ${lib.getExe applyConfig} \
                ${reducedMcpTemplate} \
                ${reducedHooksTemplate} \
                ${reducedPluginsTemplate} \
                ${permissionsTemplate} \
                ${reducedStateTemplate} \
                ${reducedCliTemplate} \
                ${reducedHubTemplate} \
                "$xdg2"
              check "$xdg2/Antigravity/app_storage.json" '.autoCheckForUpdates' '"true"'
              check "$xdg2/Antigravity/app_storage.json" '.runInBackground' '"false"'
              ${lib.getExe applyConfig} \
                ${reducedMcpTemplate} \
                ${reducedHooksTemplate} \
                ${reducedPluginsTemplate} \
                ${permissionsTemplate} \
                ${reducedStateTemplate} \
                ${reducedCliTemplate} \
                ${reducedHubTemplate} \
                "$xdg1"
              check "$xdg1/Antigravity/app_storage.json" 'has("autoCheckForUpdates")' false
              check "$xdg2/Antigravity/app_storage.json" '.autoCheckForUpdates' '"true"'
              check "$HOME/.gemini/config/.nix-managed.json" '.hubStorageByTarget' '{}'

              # 5. Corrupt .nix-managed.json fails --check and apply before touching live files or cleaning migrated-settings.
              seed corrupt-state
              put ${liveConfig} "$HOME/.gemini/config/config.json"
              printf 'not json' >"$HOME/.gemini/config/.nix-managed.json"
              if ${lib.getExe applyConfig} --check "" "" "" "" "" ${cliSettingsTemplate} ${hubStorageTemplate}; then
                echo "FAIL: --check accepted corrupt .nix-managed.json" >&2
                exit 1
              fi
              if apply; then
                echo "FAIL: corrupt .nix-managed.json accepted" >&2
                exit 1
              fi
              jq '. + { hubStorageByTarget: 123 }' ${stateTemplate} >"$HOME/.gemini/config/.nix-managed.json"
              if ${lib.getExe applyConfig} --check "" "" "" "" "" ${cliSettingsTemplate} ${hubStorageTemplate}; then
                echo "FAIL: --check accepted non-object hubStorageByTarget" >&2
                exit 1
              fi
              jq '. + { hubStorageByTarget: { "/tmp/a": [123] } }' ${stateTemplate} >"$HOME/.gemini/config/.nix-managed.json"
              if ${lib.getExe applyConfig} --check "" "" "" "" "" ${cliSettingsTemplate} ${hubStorageTemplate}; then
                echo "FAIL: --check accepted non-string element in hubStorageByTarget" >&2
                exit 1
              fi
              cmp ${liveConfig} "$HOME/.gemini/config/config.json"
              [ -d "$HOME/.gemini/config/plugins/migrated-settings" ]

              # 6. Non-object live files fail --check and apply before replacing earlier staged files or deleting migrated-settings.
              seed non-object-live
              put ${liveMcp} "$HOME/.gemini/config/mcp_config.json"
              printf '[]' >"$HOME/.gemini/config/config.json"
              if ${lib.getExe applyConfig} --check "" "" "" "" "" ${cliSettingsTemplate} ${hubStorageTemplate}; then
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

              seed non-object-hub
              put ${liveConfig} "$HOME/.gemini/config/config.json"
              mkdir -p "$HOME/.config/Antigravity"
              printf '[]' >"$HOME/.config/Antigravity/app_storage.json"
              if ${lib.getExe applyConfig} --check "" "" "" "" "" "" ${hubStorageTemplate}; then
                echo "FAIL: --check accepted array app_storage.json" >&2
                exit 1
              fi
              if apply; then
                echo "FAIL: array app_storage.json accepted" >&2
                exit 1
              fi
              cmp ${liveConfig} "$HOME/.gemini/config/config.json"
              [ "$(cat "$HOME/.config/Antigravity/app_storage.json")" = "[]" ]

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

        "antigravity-cli/no-google-telemetry" =
          let
            cliSettings = import ./_settings.nix;
            rawAgyPkg = inputs.llm-agents.packages.${system}.antigravity-cli;
            telemetryShell = import ./_shell.nix {
              inherit lib pkgs;
              scratchDir = "/nonexistent/agy-telemetry-scratch";
            };
            stubRawAgy = pkgs.writeShellScriptBin "agy" ''
              printf 'ARGV:'
              for arg in "$@"; do
                printf ' [%s]' "$arg"
              done
              printf '\nENV:AGY_CLI_DISABLE_AUTO_UPDATE=%s|NO_CFG=%s|NO_STATS=%s|NO_UPD=%s\n' \
                "''${AGY_CLI_DISABLE_AUTO_UPDATE:-}" \
                "''${CHROME_DEVTOOLS_MCP_NO_CONFIG_DISCOVERY:-}" \
                "''${CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS:-}" \
                "''${CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS:-}"
            '';
            wrappedStubAgy = telemetry.wrapAgy {
              inherit lib pkgs;
              package = stubRawAgy;
              shell = telemetryShell;
              scratchDir = "/nonexistent/agy-telemetry-scratch";
            };
            songbirdCfg =
              if system == "x86_64-linux" && config.flake.nixosConfigurations ? songbird then
                config.flake.nixosConfigurations.songbird.config
              else
                null;
            songbirdHm =
              if songbirdCfg != null then songbirdCfg.home-manager.users.${metaOwner.username} else null;
            songbirdCliEnabled =
              songbirdCfg != null && (songbirdCfg.programs."antigravity-cli".extended.enable or false);
            songbirdHubEnabled =
              songbirdCfg != null && (songbirdCfg.programs."antigravity-hub".extended.enable or false);
            songbirdAnyEnabled = songbirdCliEnabled || songbirdHubEnabled;
            wrappedRealAgy =
              if songbirdCliEnabled then
                songbirdCfg.programs."antigravity-cli".extended.finalPackage
              else
                telemetry.wrapAgy {
                  inherit lib pkgs;
                  package = rawAgyPkg;
                  shell = telemetryShell;
                  scratchDir = "/nonexistent/agy-telemetry-scratch";
                };
            hasHubPkg =
              pkgs.stdenv.hostPlatform.isLinux && inputs.llm-agents.packages.${system} ? antigravity-hub;
            fallbackHubBase = inputs.llm-agents.packages.${system}.antigravity-hub.override {
              languageServerFlags = [
                "--https_server_port=7777"
                "--remote_accessible"
              ]
              ++ telemetry.languageServerFlags;
            };
            fallbackHubPkg = pkgs.symlinkJoin (
              {
                name = "antigravity-hub-test-${fallbackHubBase.version or "custom"}";
                paths = [ fallbackHubBase ];
                nativeBuildInputs = [ pkgs.makeWrapper ];
                postBuild = ''
                  wrapProgram "$out/bin/antigravity" \
                    ${lib.concatStringsSep " " (
                      lib.mapAttrsToList (
                        name: value: "--set ${lib.escapeShellArg name} ${lib.escapeShellArg value}"
                      ) telemetry.sharedEnv
                    )}
                '';
              }
              // lib.optionalAttrs (fallbackHubBase ? version) { inherit (fallbackHubBase) version; }
              // lib.optionalAttrs (fallbackHubBase ? meta) { inherit (fallbackHubBase) meta; }
            );
            deployedHubPkg =
              if songbirdHubEnabled then
                songbirdCfg.programs."antigravity-hub".extended.finalPackage
              else if hasHubPkg then
                fallbackHubPkg
              else
                null;
            expectedSubcommands = lib.sort lib.lessThan telemetry.knownSubcommands;
            sharedEnvChecks = lib.concatMapStringsSep "\n" (
              name:
              ''grep -qE "^export ${name}=['\"]?1['\"]?" "$hubBin" || { echo "FAIL: Hub launcher missing ${name}=1" >&2; exit 1; }''
            ) (lib.attrNames telemetry.sharedEnv);
            renderedInstructions =
              if songbirdAnyEnabled then
                songbirdHm.home.file.".gemini/config/AGENTS.md".text
              else
                config.flake.lib.agents.systemPrompt.render {
                  vars = {
                    questionTool = "ask_question";
                    sbx = true;
                  };
                };
            expectSbxRule =
              if songbirdAnyEnabled then config.flake.lib.agents.skills.sbx.enabledOn songbirdCfg else true;
          in
          assert lib.assertMsg (
            !(cliSettings.showFeedbackSurvey or true)
          ) "antigravity-cli: _settings.nix must disable showFeedbackSurvey";
          assert lib.assertMsg (
            (telemetry.hubStorage.autoCheckForUpdates or null) == "false"
          ) "antigravity-cli: telemetry.hubStorage.autoCheckForUpdates must be string \"false\"";
          assert lib.assertMsg (lib.elem "--disable_telemetry" telemetry.languageServerFlags)
            "antigravity-cli: telemetry.languageServerFlags must include --disable_telemetry";
          assert lib.assertMsg (
            (telemetry.cliEnv.AGY_CLI_DISABLE_AUTO_UPDATE or null) == "1"
          ) "antigravity-cli: telemetry.cliEnv.AGY_CLI_DISABLE_AUTO_UPDATE must be \"1\"";
          assert lib.assertMsg (
            (telemetry.cliEnv.CHROME_DEVTOOLS_MCP_NO_CONFIG_DISCOVERY or null) == "1"
            && (telemetry.cliEnv.CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS or null) == "1"
            && (telemetry.cliEnv.CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS or null) == "1"
          ) "antigravity-cli: CHROME_DEVTOOLS_MCP_NO_* variables must be \"1\"";
          assert lib.assertMsg (
            !songbirdAnyEnabled
            || lib.hasInfix (lib.escapeShellArg songbirdHm.xdg.configHome) songbirdHm.home.activation.antigravitySetup.data
          ) "antigravity-cli: HM antigravitySetup must pass evaluated xdg.configHome";
          assert lib.assertMsg (lib.hasInfix "`ask_question`" renderedInstructions)
            "antigravity-cli: rendered AGENTS.md must reference `ask_question`";
          assert lib.assertMsg (
            !expectSbxRule || lib.hasInfix "`sbx` VM" renderedInstructions
          ) "antigravity-cli: rendered AGENTS.md must include `sbx` VM rule when sbx is enabled";
          assert lib.assertMsg (
            !(lib.hasPrefix "---" (lib.trim renderedInstructions))
          ) "antigravity-cli: rendered AGENTS.md must not start with YAML frontmatter";
          assert lib.assertMsg (
            builtins.stringLength renderedInstructions <= 24000
          ) "antigravity-cli: rendered AGENTS.md exceeds Antigravity 24000-character global rule limit";
          pkgs.runCommandLocal "antigravity-cli-no-google-telemetry" { passthru.runtimeCheck = true; } ''
            set -euo pipefail
            mkdir -p "$TMPDIR/home"

            stubAgy=${lib.getExe wrappedStubAgy}
            realAgy=${lib.getExe wrappedRealAgy}

            expect_stub() {
              local expected=$1
              shift
              local out argv_line env_line
              out="$(env -i HOME="$TMPDIR/home" PATH="${pkgs.coreutils}/bin" "$stubAgy" "$@")"
              argv_line="$(printf '%s\n' "$out" | grep '^ARGV:')"
              env_line="$(printf '%s\n' "$out" | grep '^ENV:')"
              if [ "$argv_line" != "ARGV:$expected" ]; then
                echo "FAIL: stub agy $* -> expected 'ARGV:$expected', got '$argv_line'" >&2
                exit 1
              fi
              if [ "$env_line" != "ENV:AGY_CLI_DISABLE_AUTO_UPDATE=1|NO_CFG=1|NO_STATS=1|NO_UPD=1" ]; then
                echo "FAIL: stub agy $* -> unexpected env '$env_line'" >&2
                exit 1
              fi
            }

            expect_reject_stub() {
              if env -i HOME="$TMPDIR/home" PATH="${pkgs.coreutils}/bin" "$stubAgy" "$@" >/dev/null 2>&1; then
                echo "FAIL: stub agy $* unexpectedly succeeded" >&2
                exit 1
              fi
            }

            expect_stub ""
            expect_stub " [-p] [hi]" -p hi
            expect_stub " [--] [--disable_telemetry=false]" -- --disable_telemetry=false
            expect_stub " [fix bug]" "fix bug"
            expect_stub " [acp] [--disable_telemetry] [--stdio]" acp --stdio
            expect_stub " [acp] [--disable_telemetry] [--disable_telemetry=true] [--stdio]" acp --disable_telemetry=true --stdio
            expect_stub " [acp] [--disable_telemetry] [--stdio] [--] [--disable_telemetry=false]" acp --stdio -- --disable_telemetry=false

            expect_reject_stub acp --disable_telemetry=false
            expect_reject_stub acp -disable_telemetry=0
            expect_reject_stub acp --disable-telemetry=f
            expect_reject_stub acp -disable-telemetry=

            help_out="$(env -i HOME="$TMPDIR/home" PATH="${pkgs.coreutils}/bin" "$realAgy" --help 2>&1)"
            if printf '%s\n' "$help_out" | grep -qE 'disable[-_]telemetry'; then
              echo "FAIL: root agy --help now exposes disable_telemetry; update wrapAgy to inject it there too" >&2
              exit 1
            fi
            actual_subs="$(
              awk '
                /^Available subcommands:$/ { in_subs = 1; next }
                in_subs && /^[[:space:]]*$/ { exit }
                in_subs && /^[[:space:]]+[a-z0-9-]+/ { print $1 }
              ' <<<"$help_out" | LC_ALL=C sort
            )"
            expected_subs=${lib.escapeShellArg (lib.concatStringsSep "\n" expectedSubcommands)}
            if [ "$actual_subs" != "$expected_subs" ]; then
              printf 'FAIL: antigravity-cli (${rawAgyPkg.version}) subcommands drifted.\nexpected:\n%s\ngot:\n%s\n' \
                "$expected_subs" "$actual_subs" >&2
              exit 1
            fi

            root_flag_err="$(env -i HOME="$TMPDIR/home" PATH="${pkgs.coreutils}/bin" "$realAgy" --input-format invalid 2>&1 || true)"
            printf '%s\n' "$root_flag_err" | grep -qF 'unknown --input-format' || {
              echo "FAIL: unexpected root flag error: $root_flag_err" >&2
              exit 1
            }
            if printf '%s\n' "$root_flag_err" | grep -qF 'flags provided but not defined'; then
              echo "FAIL: root agy rejected wrapper flags: $root_flag_err" >&2
              exit 1
            fi

            acp_flag_err="$(env -i HOME="$TMPDIR/home" PATH="${pkgs.coreutils}/bin" "$realAgy" acp --unknown-telemetry-check 2>&1 || true)"
            printf '%s\n' "$acp_flag_err" | grep -qF 'flags provided but not defined: -unknown-telemetry-check' || {
              echo "FAIL: acp did not accept injected --disable_telemetry: $acp_flag_err" >&2
              exit 1
            }

            for sub in acp plugin mcp models; do
              env -i HOME="$TMPDIR/home" PATH="${pkgs.coreutils}/bin" "$realAgy" "$sub" --help >/dev/null
            done

            ${lib.optionalString (hasHubPkg && deployedHubPkg != null) ''
              hubBin=${lib.getExe deployedHubPkg}
              lsBin=${lib.escapeShellArg "${deployedHubPkg}/share/antigravity/resources/bin/language_server"}
              ${sharedEnvChecks}
              grep -qF -- '--disable_telemetry' "$lsBin" || {
                echo "FAIL: Hub language_server wrapper missing --disable_telemetry" >&2
                exit 1
              }
              stampOut="$(env -i HOME="$TMPDIR/home" PATH="${pkgs.coreutils}/bin" "$lsBin" --stamp 2>&1)"
              printf '%s\n' "$stampOut" | grep -qF 'Built at CL:' || {
                echo "FAIL: Hub language_server --stamp unexpected output: $stampOut" >&2
                exit 1
              }
            ''}

            echo "ok: antigravity no-google-telemetry contract" >$out
          '';
      };
    };
}
