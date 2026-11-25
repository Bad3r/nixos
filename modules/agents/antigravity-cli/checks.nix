{
  config,
  inputs,
  lib,
  ...
}:
let
  telemetry = import ./_telemetry.nix;
  binaryPatches = import ./_binary-patches.nix;
  proxy = import ./_proxy.nix;
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
        userSettingsFile = null;
        stateFile = null;
        hubStorageFile = null;
      };
      inherit (activation) applyConfig agentapiShimsScript;

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
      userSettingsTemplate = json "user-settings-template.json" {
        globalPermissionGrants = {
          allow = [ "command(git)" ];
          ask = [ "command(git push --force)" ];
          deny = [ "command(/bin/rm)" ];
        };
        themeMode = "THEME_MODE_DARK";
        customThemeSeedsDark = {
          background = "#121314";
          foregroundOverride = "#bbbebf";
          primary = "#3994bc";
        };
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
        userSettings = [
          "customThemeSeedsDark"
          "themeMode"
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
      reducedUserSettingsTemplate = json "user-settings-reduced.json" {
        globalPermissionGrants.allow = [ "command(git)" ];
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
          customThemeSeedsDark = {
            primary = "#007acc";
            codeForegroundOverride = "#ffffff";
          };
          customThemeSeedsLight.primary = "#007acc";
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
                  ${userSettingsTemplate} \
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
              check "$cfg" '.userSettings.customThemeSeedsDark' '{"background":"#121314","foregroundOverride":"#bbbebf","primary":"#3994bc"}'
              check "$cfg" '.userSettings.customThemeSeedsLight.primary' '"#007acc"'
              check "$cfg" '.userSettings.themeMode' '"THEME_MODE_DARK"'
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
                ${reducedUserSettingsTemplate} \
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
              check "$cfg" '.userSettings | has("customThemeSeedsDark")' false
              check "$cfg" '.userSettings | has("themeMode")' false
              check "$cfg" '.userSettings.customThemeSeedsLight.primary' '"#007acc"'
              check "$cfg" '.userSettings.globalPermissionGrants.allow' '["command(git)"]'
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
                ${userSettingsTemplate} \
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
                ${userSettingsTemplate} \
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
                ${userSettingsTemplate} \
                ${stateTemplate} \
                ${cliSettingsTemplate} \
                ${hubStorageTemplate}
              ${lib.getExe applyConfig} \
                ${mcpTemplate} \
                ${hooksTemplate} \
                ${pluginsTemplate} \
                ${userSettingsTemplate} \
                ${reducedStateTemplate} \
                "" \
                ""
              check "$HOME/.gemini/config/.nix-managed.json" '.cliSettings' '["agentMode","permissions","toolPermission"]'
              check "$HOME/.gemini/config/.nix-managed.json" '.hubStorageByTarget[$ENV.HOME + "/.config/Antigravity/app_storage.json"]' '["autoCheckForUpdates"]'
              ${lib.getExe applyConfig} \
                ${reducedMcpTemplate} \
                ${reducedHooksTemplate} \
                ${reducedPluginsTemplate} \
                ${userSettingsTemplate} \
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
                ${userSettingsTemplate} \
                ${stateTemplate} \
                ${cliSettingsTemplate} \
                ${hubStorageTemplate} \
                "$xdg1"
              put ${liveHubStorage} "$xdg2/Antigravity/app_storage.json"
              ${lib.getExe applyConfig} \
                ${reducedMcpTemplate} \
                ${reducedHooksTemplate} \
                ${reducedPluginsTemplate} \
                ${userSettingsTemplate} \
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
                ${userSettingsTemplate} \
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

        "antigravity-cli/binary-patches" =
          let
            unpatched = inputs.llm-agents.packages.${system}.antigravity-cli;
            patched = binaryPatches.patchAgy {
              inherit lib pkgs;
              package = unpatched;
              patches = binaryPatches.patchSets;
            };
          in
          pkgs.runCommandLocal "antigravity-cli-binary-patches"
            {
              passthru.runtimeCheck = true;
              nativeBuildInputs = [
                pkgs.jq
                pkgs.python3
              ];
            }
            ''
              set -euo pipefail
              manifest=${patched}/share/antigravity-cli/agy.patch.json
              fail() { echo "FAIL: $*" >&2; exit 1; }

              [ "$(jq -r '.patches | join(",")' "$manifest")" = ${lib.escapeShellArg (lib.concatStringsSep "," binaryPatches.patchSets)} ] || fail "manifest patch sets"
              [ "$(jq -r .input_sha256 "$manifest")" = "$(sha256sum ${unpatched}/bin/agy | cut -d' ' -f1)" ] \
                || fail "input checksum"
              [ "$(jq -r .output_sha256 "$manifest")" = "$(sha256sum ${patched}/bin/agy | cut -d' ' -f1)" ] \
                || fail "output checksum"
              ! grep -q ${lib.escapeShellArg (builtins.unsafeDiscardStringContext (toString unpatched))} "$manifest" \
                || fail "manifest references the unpatched package"

              # The binaries differ in exactly the bytes the manifest's edits change.
              expected=$(jq '[.edits[] | . as $e | [range(0; $e.orig | length; 2) | select($e.orig[.:.+2] != $e.new[.:.+2])] | length] | add' "$manifest")
              actual=$(cmp -l ${unpatched}/bin/agy ${patched}/bin/agy | wc -l || true)
              [ "$actual" -eq "$expected" ] || fail "$actual bytes differ, manifest edits change $expected"

              # Every set on 1.5.17 gives exactly this binary.
              [ "$(jq -r .version "$manifest")" != 1.5.17 ] \
                || [ "$(jq -r .output_sha256 "$manifest")" = 632fcc0d8c113db1fcc1e79244849c6ebd28f8a0d19c7fef4d432dc9fe528e6a ] \
                || fail "1.5.17 output checksum drifted"

              # agygating disables sir_flash_lite and severe_internal_risks_agy, drops the latter
              # to ASK, and changes no other monitor field.
              python3 -I -c '
              import re, sys
              header = re.compile(rb"monitors \{\n +name: \x22([^\x22]+)\x22\n((?: +[a-z_]+: [^\n]*\n)+)")
              def monitors(path):
                  data = open(path, "rb").read()
                  return {
                      m[1].decode(): {k.decode(): v.decode().strip() for k, v in re.findall(rb"^ *([a-z_]+): (.*)$", m[2], re.M)}
                      for m in header.finditer(data)
                  }
              shipped, patched = map(monitors, sys.argv[1:])
              assert {"sir_flash_lite", "severe_internal_risks_agy"} <= shipped.keys(), shipped.keys()
              assert shipped["sir_flash_lite"]["enabled"] == shipped["severe_internal_risks_agy"]["enabled"] == "true", shipped
              expected = {name: dict(fields) for name, fields in shipped.items()}
              expected["sir_flash_lite"]["enabled"] = "false"
              expected["severe_internal_risks_agy"].update(enabled="false", mode="ASK")
              assert patched == expected, patched
              ' ${unpatched}/bin/agy ${patched}/bin/agy || fail "agygating monitor fields"

              # A build the patcher does not know fails instead of passing through unpatched.
              cp ${unpatched}/bin/agy "$TMPDIR/agy-unknown"
              chmod u+w "$TMPDIR/agy-unknown"
              printf 'x' | dd of="$TMPDIR/agy-unknown" bs=1 seek=64 conv=notrunc status=none
              if python3 -I ${./_patch_agy.py} "$TMPDIR/agy-unknown" "$TMPDIR/agy-out" 2>"$TMPDIR/unknown.err"; then
                fail "patched an unknown build"
              fi
              grep -q 'unknown agy build' "$TMPDIR/unknown.err" || fail "unknown build error message"
              [ ! -e "$TMPDIR/agy-out" ] || fail "wrote output for an unknown build"
              rm -f "$TMPDIR/agy-unknown"

              # The patched binary still starts.
              HOME="$TMPDIR" ${patched}/bin/agy --help 2>&1 | grep -q 'Usage of agy' || fail "agy --help"

              # Offline print mode, signed out: the unpatched binary reaches the updater (which skips a
              # read-only store directory) and fails to flush Clearcut telemetry at exit; the patched
              # one does neither.
              run_print() {
                mkdir -p "$TMPDIR/home-$2"
                HOME="$TMPDIR/home-$2" timeout 25 "$1" -p hi --log-file "$TMPDIR/$2.log" </dev/null >/dev/null 2>&1 || true
              }
              run_print ${unpatched}/bin/agy unpatched
              run_print ${patched}/bin/agy patched
              grep -q -E 'Spawned background update process|is not fully accessible.*skipping update' "$TMPDIR/unpatched.log" \
                || fail "unpatched: updater not reached (test is blind)"
              grep -q 'telemetry client' "$TMPDIR/unpatched.log" || fail "unpatched: no telemetry flush (test is blind)"
              grep -q 'Auto-update disabled' "$TMPDIR/patched.log" || fail "patched: updater not disabled"
              ! grep -q -E 'Spawned background update process|is not fully accessible.*skipping update' "$TMPDIR/patched.log" \
                || fail "patched: updater reached"
              ! grep -q 'telemetry client' "$TMPDIR/patched.log" || fail "patched: telemetry client active"
              ! grep -q 'skipping empty or temp file' "$TMPDIR/patched.log" || fail "patched: file_watcher log line"

              echo "ok: agy binary patches ($expected bytes)" >$out
            '';

        "antigravity-cli/agentapi-shims" =
          pkgs.runCommandLocal "antigravity-cli-agentapi-shims" { passthru.runtimeCheck = true; }
            ''
              set -euo pipefail
              shims() { PATH="/nonexistent" ${lib.getExe agentapiShimsScript} "$@"; }
              target="$TMPDIR/bin/agy"
              mkdir -p "$TMPDIR/bin" "$TMPDIR/cli/bin" "$TMPDIR/hub"
              printf '#!/bin/sh\n' >"$target"
              chmod +x "$target"
              printf '#!/bin/sh\nexec "/nix/store/old/bin/agy" agentapi "$@"\n' >"$TMPDIR/cli/bin/agentapi"
              expected=$(printf '#!/bin/sh\nexec "%s" agentapi "$@"' "$target")

              # 1. A stale shim is rewritten, a missing bin/ is created, a missing app dir is skipped.
              shims "$TMPDIR/cli" "$target" "$TMPDIR/hub" "$target" "$TMPDIR/ide" "$target" >"$TMPDIR/out1"
              for dir in cli hub; do
                [ "$(cat "$TMPDIR/$dir/bin/agentapi")" = "$expected" ] || { echo "FAIL: $dir shim" >&2; exit 1; }
                [ -x "$TMPDIR/$dir/bin/agentapi" ] || { echo "FAIL: $dir shim not executable" >&2; exit 1; }
              done
              [ ! -e "$TMPDIR/ide" ] || { echo "FAIL: created a missing app dir" >&2; exit 1; }
              [ "$(wc -l <"$TMPDIR/out1")" -eq 2 ] || { echo "FAIL: expected 2 rewrites" >&2; exit 1; }

              # 2. A second run changes nothing and leaves no temp files.
              shims "$TMPDIR/cli" "$target" "$TMPDIR/hub" "$target" >"$TMPDIR/out2"
              [ ! -s "$TMPDIR/out2" ] || { echo "FAIL: second run rewrote a shim" >&2; exit 1; }
              [ -z "$(find "$TMPDIR/cli/bin" "$TMPDIR/hub/bin" -name '.agentapi.*')" ] || { echo "FAIL: temp file left" >&2; exit 1; }

              # 3. A non-executable target leaves the shim alone with a warning.
              shims "$TMPDIR/cli" "$TMPDIR/missing/agy" 2>"$TMPDIR/err3"
              grep -q 'not executable' "$TMPDIR/err3" || { echo "FAIL: no warning" >&2; exit 1; }
              [ "$(cat "$TMPDIR/cli/bin/agentapi")" = "$expected" ] || { echo "FAIL: shim changed" >&2; exit 1; }

              # 4. Targets that would break the double-quoted exec are refused, and odd argument counts fail.
              if shims "$TMPDIR/cli" '/x/"$(id)"' 2>/dev/null; then echo "FAIL: accepted unsafe target" >&2; exit 1; fi
              if shims "$TMPDIR/cli" 2>/dev/null; then echo "FAIL: accepted odd argument count" >&2; exit 1; fi

              echo "ok: antigravity-agentapi-shims contract" >$out
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

        "antigravity-cli/proxy-overrides" =
          let
            dummyAgy = pkgs.writeShellScriptBin "agy" ''
              printf 'ARGS:%s\n' "$*"
              printf 'TEMPLATE_DATA_DIR=%s\n' "''${TEMPLATE_DATA_DIR-UNSET}"
              printf 'HTTPS_PROXY=%s\n' "''${HTTPS_PROXY-UNSET}"
              printf 'SSL_CERT_FILE=%s\n' "''${SSL_CERT_FILE-UNSET}"
              printf 'NODE_EXTRA_CA_CERTS=%s\n' "''${NODE_EXTRA_CA_CERTS-UNSET}"
              printf 'ANTIGRAVITY_PROXY_ACTIVE=%s\n' "''${ANTIGRAVITY_PROXY_ACTIVE-UNSET}"
              printf 'ANTIGRAVITY_ORIG_SSL_CERT_FILE=%s\n' "''${ANTIGRAVITY_ORIG_SSL_CERT_FILE-UNSET}"
              if [ "''${RUN_NESTED_BASH:-0}" = "1" ]; then
                bash -c 'printf "CHILD:HTTPS_PROXY=%s SSL_CERT_FILE=%s ACTIVE=%s ORIG=%s PIN=%s\n" "''${HTTPS_PROXY-UNSET}" "''${SSL_CERT_FILE-UNSET}" "''${ANTIGRAVITY_PROXY_ACTIVE-UNSET}" "''${ANTIGRAVITY_ORIG_SSL_CERT_FILE-UNSET}" "''${ANTIGRAVITY_PIN_SSL_CERT_FILE-UNSET}"'
              fi
            '';
            testProxyCfg = {
              enable = true;
              port = 18099;
              guidelinesOverride = "strip";
              guidelinesPin = proxy.defaultGuidelinesPin;
              flagOverrides = {
                "generic-system-prompt" = false;
                "enable-programmatic-tools" = true;
              };
              package = pkgs.mitmproxy;
            };
            wrappedDummyAgy = telemetry.wrapAgy {
              inherit lib pkgs shell;
              package = dummyAgy;
              scratchDir = "/nonexistent/agy-proxy-check-missing";
              templatesDir = proxy.defaultTemplatesDir;
              proxy = testProxyCfg;
            };
            hubWrapperScript = pkgs.writeShellScript "antigravity-hub-test-wrapper" ''
              set -euo pipefail
              ${proxy.mkWrapperEnvSnippet {
                inherit lib;
                templatesDir = proxy.defaultTemplatesDir;
                proxy = testProxyCfg;
                isHub = true;
              }}
              printf 'HUB_ARGS:%s\n' "$*"
              printf 'HUB_PIN_TPL=%s\n' "''${ANTIGRAVITY_PIN_TEMPLATE_DATA_DIR-UNSET}"
              printf 'HUB_PIN_SSL=%s\n' "''${ANTIGRAVITY_PIN_SSL_CERT_FILE-UNSET}"
              # Simulate Electron overwriting SSL_CERT_FILE and TEMPLATE_DATA_DIR from login shell.
              export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
              export TEMPLATE_DATA_DIR=/wrong/templates
              ${proxy.restorePinnedEnvSnippet lib}
              printf 'LS_RESTORED_TPL=%s\n' "''${TEMPLATE_DATA_DIR-UNSET}"
              printf 'LS_RESTORED_SSL=%s\n' "''${SSL_CERT_FILE-UNSET}"
              printf 'LS_RESTORED_PIN=%s\n' "''${ANTIGRAVITY_PIN_SSL_CERT_FILE-UNSET}"
            '';
            proxyStartScript = proxy.mkProxyStartScript {
              inherit lib pkgs;
              proxy = testProxyCfg // {
                port = 0;
              };
              systemCaBundle = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            };
          in
          pkgs.runCommandLocal "antigravity-cli-proxy-overrides"
            {
              passthru.runtimeCheck = true;
              nativeBuildInputs = [
                pkgs.openssl
                pkgs.python3
              ];
            }
            ''
              set -euo pipefail
              fail() { echo "FAIL: $*" >&2; exit 1; }

              # 1. Bundled templates exist and include guidelines + identity.
              [ -s ${proxy.defaultTemplatesDir}/system_prompts/guidelines.tmpl ] || fail "missing guidelines.tmpl"
              [ -s ${proxy.defaultTemplatesDir}/system_prompts/identity.tmpl ] || fail "missing identity.tmpl"
              [ "$(find ${proxy.defaultTemplatesDir} -name '*.tmpl' | wc -l)" -eq 19 ] || fail "expected 19 templates"

              # 2. Offline unit tests of _proxy_overrides.py (pin parsing, flags, guidelines drift & rewrite, allow_hosts regex).
              python3 -I - ${proxy.addonScript} ${proxy.defaultGuidelinesPin} ${lib.escapeShellArg proxy.allowHostsRegex} <<'PY'
              import hashlib, importlib.util, pathlib, re, sys

              addon_path, pin_path, allow_re = sys.argv[1], sys.argv[2], sys.argv[3]
              spec = importlib.util.spec_from_file_location("proxy_overrides", addon_path)
              mod = importlib.util.module_from_spec(spec)
              spec.loader.exec_module(mod)

              pin = mod.read_pin(pin_path)
              assert len(pin) == 64

              # allow_hosts matches only Google API endpoints rewritten by the addon.
              pat = re.compile(allow_re)
              for host in (
                  "daily-cloudcode-pa.googleapis.com:443",
                  "cloudcode-pa.googleapis.com:443",
                  "aicode.googleapis.com:443",
                  "daily-cloudcode-pa.googleapis.com",
              ):
                  assert pat.search(host), f"allow_hosts missed {host}"
              for host in (
                  "api.github.com:443",
                  "oauth2.googleapis.com:443",
                  "evil-cloudcode-pa.googleapis.com:443",
                  "daily-cloudcode-pa.googleapis.com.evil.com:443",
              ):
                  assert not pat.search(host), f"allow_hosts matched {host}"

              # Mendel flag parsing and rewriting.
              overrides = mod.parse_flag_overrides("a=false,b=42,c=1.5,d=hello")
              assert overrides["a"][:2] == ("boolValue", False)
              assert overrides["b"][:2] == ("intValue", "42")
              assert overrides["c"][:2] == ("floatValue", 1.5)
              assert overrides["d"][:2] == ("stringValue", "hello")

              cfg_body = {"experimentConfig": {"experimentFlags": [{"name": "a", "stringValue": "true"}]}}
              changed = mod.rewrite_flags(cfg_body, "/v1alpha:fetchConfig", overrides)
              assert set(changed) == {"a", "b", "c", "d"}
              flags_by_name = {f["name"]: f for f in cfg_body["experimentConfig"]["experimentFlags"]}
              assert flags_by_name["a"] == {"name": "a", "stringValue": "false"}
              assert flags_by_name["b"] == {"name": "b", "intValue": "42"}

              # Guidelines check + strip + replace + drift detection.
              sample_text = "pinned guidelines body"
              sample_pin = hashlib.sha256(sample_text.encode("utf-8")).hexdigest()
              ok_body = {
                  "models": {
                      "gemini-4-hydrogen-high": {
                          "modelExperiments": {
                              "experiments": {
                                  mod.GUIDELINES_KEY: {"stringValue": sample_text},
                                  "other-flag": {"boolValue": True},
                              }
                          }
                      },
                      "other-model": {"modelExperiments": {"experiments": {}}},
                  }
              }
              problems, unpinned, found = mod.check_guidelines(ok_body, sample_pin, "strip")
              assert problems == [] and unpinned == {} and found == 1

              # Extra template__* key fails drift check.
              extra_body = {
                  "models": {
                      "m": {
                          "modelExperiments": {
                              "experiments": {
                                  mod.GUIDELINES_KEY: {"stringValue": sample_text},
                                  "template__system_prompts__identity": {"stringValue": "x"},
                              }
                          }
                      }
                  }
              }
              problems, _, _ = mod.check_guidelines(extra_body, sample_pin, "strip")
              assert any("unpinned server template reference" in p for p in problems), problems

              # Hash mismatch reports drift and returns unpinned text.
              drift_body = {
                  "models": {
                      "m": {"modelExperiments": {"experiments": {mod.GUIDELINES_KEY: {"stringValue": "changed"}}}}
                  }
              }
              problems, unpinned, found = mod.check_guidelines(drift_body, sample_pin, "strip")
              assert len(problems) == 1 and len(unpinned) == 1 and found == 1

              # Missing key fails in replacement-file mode.
              problems, _, found = mod.check_guidelines({"models": {}}, sample_pin, "/tmp/custom.tmpl")
              assert len(problems) == 1 and found == 0

              # Strip deletes only the guidelines key.
              touched = mod.rewrite_guidelines(ok_body, "strip")
              assert touched == ["models.gemini-4-hydrogen-high"]
              assert mod.GUIDELINES_KEY not in ok_body["models"]["gemini-4-hydrogen-high"]["modelExperiments"]["experiments"]
              assert ok_body["models"]["gemini-4-hydrogen-high"]["modelExperiments"]["experiments"]["other-flag"] == {"boolValue": True}
              PY

              # 3. Real mitmdump startup via mkProxyStartScript: sd_notify READY=1, bundle.pem, and SPKI match openssl.
              export XDG_STATE_HOME="$TMPDIR/state"
              state_dir="$XDG_STATE_HOME/antigravity-proxy"
              notify_sock="$TMPDIR/notify.sock"
              python3 -I - "$notify_sock" ${proxyStartScript} "$state_dir" <<'PY'
              import os, pathlib, socket, subprocess, sys

              sock_path, start_script, state_dir = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
              srv = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
              srv.bind(sock_path)
              srv.settimeout(20.0)
              env = dict(os.environ, NOTIFY_SOCKET=sock_path, STATE_DIRECTORY=str(state_dir))
              proc = subprocess.Popen([start_script], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
              try:
                  msg, _ = srv.recvfrom(4096)
                  assert msg == b"READY=1", f"unexpected notify payload: {msg!r}"
                  # All artifacts must already exist at the moment READY=1 arrives.
                  for rel in ("bundle.pem", "spki.txt", "ca/mitmproxy-ca-cert.pem", "drift"):
                      assert (state_dir / rel).exists(), f"missing {rel} after READY=1"
              except Exception:
                  proc.terminate()
                  out, _ = proc.communicate(timeout=10)
                  sys.stderr.write(out.decode("utf-8", "replace"))
                  raise
              finally:
                  if proc.poll() is None:
                      proc.terminate()
                      proc.communicate(timeout=10)
                  srv.close()
              PY

              expected_spki=$(openssl x509 -in "$state_dir/ca/mitmproxy-ca-cert.pem" -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64)
              actual_spki=$(tr -d '[:space:]' < "$state_dir/spki.txt")
              [ "$actual_spki" = "$expected_spki" ] || fail "SPKI mismatch: got '$actual_spki', expected '$expected_spki'"
              [ "$(stat -c %a "$state_dir/bundle.pem")" = "600" ] || fail "bundle.pem permissions"
              [ "$(stat -c %a "$state_dir/spki.txt")" = "600" ] || fail "spki.txt permissions"
              grep -Fq -- "$(sed -n '2p' "$state_dir/ca/mitmproxy-ca-cert.pem")" "$state_dir/bundle.pem" || fail "bundle.pem missing proxy CA"

              # 4. agy wrapper fails closed when CA artifacts are missing, but utility subcommands still run.
              empty_state="$TMPDIR/empty-state"
              if XDG_STATE_HOME="$empty_state" ${wrappedDummyAgy}/bin/agy -p hi >/dev/null 2>"$TMPDIR/missing.err"; then
                fail "agy -p succeeded without proxy CA artifacts"
              fi
              grep -q 'antigravity-proxy CA artifacts missing' "$TMPDIR/missing.err" || fail "missing CA error text"
              XDG_STATE_HOME="$empty_state" ${wrappedDummyAgy}/bin/agy --help | grep -q '^ARGS:--help$' || fail "agy --help blocked without proxy"
              XDG_STATE_HOME="$empty_state" ${wrappedDummyAgy}/bin/agy plugin install foo | grep -q '^ARGS:plugin install foo$' || fail "agy plugin blocked without proxy"
              XDG_STATE_HOME="$empty_state" ${wrappedDummyAgy}/bin/agy agentapi status | grep -q '^ARGS:agentapi status$' || fail "agy agentapi blocked without proxy"

              # 5. agy wrapper exports TEMPLATE_DATA_DIR + proxy env, and _shell.nix restores original env for child commands.
              cli_out=$(
                unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy NO_PROXY no_proxy NODE_EXTRA_CA_CERTS TEMPLATE_DATA_DIR
                export SSL_CERT_FILE=/etc/ssl/certs/orig-ca.crt
                export XDG_STATE_HOME="$TMPDIR/state"
                export RUN_NESTED_BASH=1
                ${wrappedDummyAgy}/bin/agy -p hi
              )
              printf '%s\n' "$cli_out" | grep -Fq "TEMPLATE_DATA_DIR=${proxy.defaultTemplatesDir}" || fail "missing TEMPLATE_DATA_DIR: $cli_out"
              printf '%s\n' "$cli_out" | grep -Fq "HTTPS_PROXY=http://127.0.0.1:18099" || fail "missing HTTPS_PROXY: $cli_out"
              printf '%s\n' "$cli_out" | grep -Fq "SSL_CERT_FILE=$state_dir/bundle.pem" || fail "missing SSL_CERT_FILE: $cli_out"
              printf '%s\n' "$cli_out" | grep -Fq "NODE_EXTRA_CA_CERTS=$state_dir/ca/mitmproxy-ca-cert.pem" || fail "missing NODE_EXTRA_CA_CERTS: $cli_out"
              printf '%s\n' "$cli_out" | grep -Fq "CHILD:HTTPS_PROXY=UNSET SSL_CERT_FILE=/etc/ssl/certs/orig-ca.crt ACTIVE=UNSET ORIG=UNSET PIN=UNSET" \
                || fail "child shell did not restore pre-proxy env: $cli_out"

              # 6. Hub wrapper fails closed without spki.txt, prepends Electron flags, and language_server restores pinned env.
              if XDG_STATE_HOME="$empty_state" ${hubWrapperScript} --foo >/dev/null 2>&1; then
                fail "hub wrapper succeeded without proxy CA artifacts"
              fi
              hub_out=$(
                unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy NO_PROXY no_proxy NODE_EXTRA_CA_CERTS TEMPLATE_DATA_DIR
                export XDG_STATE_HOME="$TMPDIR/state"
                ${hubWrapperScript} --foo
              )
              printf '%s\n' "$hub_out" | grep -Fq "HUB_ARGS:--proxy-server=http://127.0.0.1:18099 --ignore-certificate-errors-spki-list=$expected_spki --foo" \
                || fail "hub args mismatch: $hub_out"
              printf '%s\n' "$hub_out" | grep -Fq "LS_RESTORED_TPL=${proxy.defaultTemplatesDir}" || fail "LS did not restore TEMPLATE_DATA_DIR: $hub_out"
              printf '%s\n' "$hub_out" | grep -Fq "LS_RESTORED_SSL=$state_dir/bundle.pem" || fail "LS did not restore SSL_CERT_FILE: $hub_out"
              printf '%s\n' "$hub_out" | grep -Fq "LS_RESTORED_PIN=UNSET" || fail "LS leaked ANTIGRAVITY_PIN_SSL_CERT_FILE: $hub_out"

              echo "ok: antigravity-cli proxy overrides and wrappers" >$out
            '';
      };
    };
}
