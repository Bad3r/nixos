/*
  Home Manager activation for Antigravity CLI and Antigravity Hub.

  antigravity-apply-config atomically merges Nix-declared entries into
  ~/.gemini/config/{mcp_config,hooks,config}.json,
  ~/.gemini/antigravity-cli/settings.json (when CLI is enabled), and
  ${XDG_CONFIG_HOME:-$HOME/.config}/Antigravity/app_storage.json (when Hub is
  enabled) while leaving runtime state (installedFrom plugin provenance,
  sidecars, custom themes, model choices, trustedWorkspaces, and UI storage)
  intact. The record lives in ~/.gemini/config/.nix-managed.json so entries
  dropped from Nix are removed on the next switch.

  Also removes artifacts left behind by an earlier migrated-settings import and
  a manual `herdr integration install` block without clobbering unrelated entries.
*/
{
  lib,
  pkgs,
  mcpServersFile,
  hooksFile,
  pluginsFile,
  permissionsFile,
  stateFile,
  cliSettingsFile ? null,
  hubStorageFile ? null,
  xdgConfigHome ? null,
  cliEnabled ? false,
  agyPkg ? null,
  marketplacePlugins ? [ ],
}:
let
  applyConfig = pkgs.writeShellApplication {
    name = "antigravity-apply-config";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.jq
    ];
    excludeShellChecks = [ "SC2016" ];
    text = ''
      check_only=0
      if [ "''${1:-}" = "--check" ]; then
        check_only=1
        shift
      fi

      mcp_template=''${1:-}
      hooks_template=''${2:-}
      plugins_template=''${3:-}
      permissions_template=''${4:-}
      state_template=''${5:-}
      cli_settings_template=''${6:-}
      hub_storage_template=''${7:-}
      xdg_config_home=''${8:-''${XDG_CONFIG_HOME:-$HOME/.config}}

      config_dir="$HOME/.gemini/config"
      cli_dir="$HOME/.gemini/antigravity-cli"
      hub_config_dir="$xdg_config_home/Antigravity"
      mcp_config="$config_dir/mcp_config.json"
      hooks_config="$config_dir/hooks.json"
      app_config="$config_dir/config.json"
      cli_settings="$cli_dir/settings.json"
      hub_storage="$hub_config_dir/app_storage.json"
      state="$config_dir/.nix-managed.json"

      tmp_files=()
      pending_srcs=()
      pending_dsts=()
      cleanup() {
        if [ "''${#tmp_files[@]}" -gt 0 ]; then
          rm -f -- "''${tmp_files[@]}"
        fi
      }
      trap cleanup EXIT

      if [ -e "$state" ]; then
        if ! jq -e --slurp '
            length == 1
            and (
              .[0]
              | type == "object"
                and .version == 1
                and (
                  [.mcpServers, .hooks, .plugins, .cliSettings]
                  | all(type == "array" and all(.[]; type == "string"))
                )
                and (
                  if has("hubStorageByTarget") then
                    (.hubStorageByTarget | type == "object" and all(.[]; type == "array" and all(.[]; type == "string")))
                  else
                    true
                  end
                )
            )
          ' "$state" >/dev/null 2>&1; then
          echo "antigravity-apply-config: $state is not a version 1 record; fix it, or delete it to reseed" >&2
          exit 1
        fi
        previous=$state
      else
        previous=$(mktemp)
        tmp_files+=("$previous")
        printf '%s\n' '{"version":1,"mcpServers":[],"hooks":[],"plugins":[],"cliSettings":[],"hubStorageByTarget":{}}' >"$previous"
      fi

      validate_target() {
        local target=$1 expr=$2
        if [ -s "$target" ]; then
          if ! jq -e --slurp --arg target "$target" "$expr" "$target" >/dev/null; then
            echo "antigravity-apply-config: $target failed validation; nothing changed" >&2
            exit 1
          fi
        fi
      }

      validate_target "$mcp_config" '
        if length == 1 and (.[0] | type) == "object"
          and ((.[0].mcpServers // {}) | type == "object")
        then true
        else error("\($target) is not a valid MCP config object") end
      '
      validate_target "$hooks_config" '
        if length == 1 and (.[0] | type) == "object" then true
        else error("\($target) is not a single JSON object") end
      '
      validate_target "$app_config" '
        if length == 1 and (.[0] | type) == "object"
          and ((.[0].plugins // {}) | type == "object" and all(.[]; type == "object"))
          and ((.[0].userSettings // {}) | type == "object"
            and ((.globalPermissionGrants // {}) | type == "object"))
        then true
        else error("\($target) is not a valid config object") end
      '
      if [ -n "$cli_settings_template" ]; then
        validate_target "$cli_settings" '
          if length == 1 and (.[0] | type) == "object" then true
          else error("\($target) is not a single JSON object") end
        '
      fi
      if [ -n "$hub_storage_template" ]; then
        validate_target "$hub_storage" '
          if length == 1 and (.[0] | type) == "object" then true
          else error("\($target) is not a single JSON object") end
        '
      fi

      if [ "$check_only" -eq 1 ]; then
        exit 0
      fi

      mkdir -p "$config_dir"
      if [ -n "$cli_settings_template" ]; then
        mkdir -p "$cli_dir"
      fi
      if [ -n "$hub_storage_template" ]; then
        mkdir -p "$xdg_config_home"
        mkdir -m 0700 "$hub_config_dir" 2>/dev/null || [ -d "$hub_config_dir" ] || mkdir -m 0700 "$hub_config_dir"
      fi

      stage_merge() {
        local target=$1 template=$2 filter=$3 extra_arg=''${4:-} tmp
        tmp=$(mktemp "$target.nix-XXXXXX")
        tmp_files+=("$tmp")
        local jq_args=(--slurp --arg target "$target" --slurpfile nix "$template" --slurpfile state "$previous")
        if [ -n "$extra_arg" ]; then
          jq_args+=(--slurpfile extra "$extra_arg")
        fi
        if ! {
          if [ -s "$target" ]; then cat -- "$target"; else printf '{}\n'; fi
        } | jq "''${jq_args[@]}" '
            if length == 1 and (.[0] | type) == "object" then .[0]
            else error("\($target) is not a single JSON object") end
            | '"$filter" >"$tmp"; then
          echo "antigravity-apply-config: $target left unchanged" >&2
          exit 1
        fi
        chmod 0600 "$tmp"
        # Skip replacing unchanged files so steady-state switches do not race running CLI or Hub saves.
        if [ -f "$target" ] && cmp -s "$tmp" "$target" && [ "$(stat -c %a "$target")" = "600" ]; then
          rm -f -- "$tmp"
          return 0
        fi
        pending_srcs+=("$tmp")
        pending_dsts+=("$target")
      }

      stage_merge "$mcp_config" "$mcp_template" '
        .mcpServers |= (
          (. // {})
          | if type == "object" then . else error("mcpServers is not an object") end
          | with_entries(select((.key | startswith("migrated-settings_")) | not))
          | reduce (($state[0].mcpServers) - ($nix[0] | keys))[] as $name (.; del(.[$name]))
          | . + $nix[0]
        )
      '

      stage_merge "$hooks_config" "$hooks_template" '
        (
          if (.herdr? | type) == "object" then
            .herdr |= (
              if (.PreInvocation? | type) == "array" then
                .PreInvocation |= map(
                  select(((.command? // "") | contains("/.gemini/config/hooks/herdr-agent-state.sh")) | not)
                )
                | if .PreInvocation == [] then del(.PreInvocation) else . end
              else .
              end
            )
            | if .herdr == {} then del(.herdr) else . end
          else .
          end
        )
        | reduce (($state[0].hooks) - ($nix[0] | keys))[] as $name (.; del(.[$name]))
        | . + $nix[0]
      '

      stage_merge "$app_config" "$plugins_template" '
        .plugins = (
          (.plugins // {})
          | if type == "object" then . else error("plugins is not an object") end
          | del(.["migrated-settings"])
          | reduce (($state[0].plugins) - ($nix[0] | keys))[] as $name (
              .;
              if has($name) and (.[$name] | type == "object") then
                .[$name] |= del(.enabled)
                | if .[$name] == {} then del(.[$name]) else . end
              else .
              end
            )
          | reduce ($nix[0] | to_entries)[] as $entry (
              .;
              .[$entry.key] = (
                (.[$entry.key] // {})
                | if type == "object" then . else error("plugin entry \($entry.key) is not an object") end
                | . + { enabled: $entry.value }
              )
            )
        )
        | .userSettings = (
            (.userSettings // {})
            | if type == "object" then . else error("userSettings is not an object") end
            | .globalPermissionGrants = (
                (.globalPermissionGrants // {})
                | if type == "object" then . else error("globalPermissionGrants is not an object") end
                | . + $extra[0]
              )
          )
      ' "$permissions_template"

      if [ -n "$cli_settings_template" ]; then
        stage_merge "$cli_settings" "$cli_settings_template" '
          $nix[0] as $declared
          | reduce (($state[0].cliSettings) - ($declared | keys))[] as $key (.; del(.[$key]))
          | . + $declared
        '
      fi

      if [ -n "$hub_storage_template" ]; then
        stage_merge "$hub_storage" "$hub_storage_template" '
          $nix[0] as $declared
          | (($state[0].hubStorageByTarget? // {})[$target] // []) as $owned
          | reduce ($owned - ($declared | keys))[] as $key (.; del(.[$key]))
          | . + $declared
        '
      fi

      hub_keys_json='[]'
      if [ -n "$hub_storage_template" ]; then
        hub_keys_json="$(jq -c 'keys' "$hub_storage_template")"
      fi

      state_tmp=$(mktemp "$state.nix-XXXXXX")
      tmp_files+=("$state_tmp")
      jq -cS --slurpfile prev "$previous" \
        --arg has_cli "$cli_settings_template" \
        --arg has_hub "$hub_storage_template" \
        --arg hub_target "$hub_storage" \
        --argjson hub_keys "$hub_keys_json" '
        ($prev[0].hubStorageByTarget? // {}) as $prev_by_target
        | (if $has_cli == "" then .cliSettings = $prev[0].cliSettings else . end)
        | .hubStorageByTarget = (
            if $has_hub == "" then
              $prev_by_target
            elif ($hub_keys | length) == 0 then
              ($prev_by_target | del(.[$hub_target]))
            else
              ($prev_by_target + { ($hub_target): $hub_keys })
            end
          )
      ' "$state_template" >"$state_tmp"
      chmod 0600 "$state_tmp"
      if [ ! -f "$state" ] || ! cmp -s "$state_tmp" "$state" || [ "$(stat -c %a "$state")" != "600" ]; then
        pending_srcs+=("$state_tmp")
        pending_dsts+=("$state")
      else
        rm -f -- "$state_tmp"
      fi

      had_migrated=0
      for marker in \
        "$config_dir/plugins/migrated-settings" \
        "$HOME/.gemini/antigravity/plugin_data/migrated-settings" \
        "$cli_dir/plugin_data/migrated-settings"; do
        if [ -e "$marker" ]; then
          had_migrated=1
          break
        fi
      done

      for i in "''${!pending_srcs[@]}"; do
        mv -f -- "''${pending_srcs[$i]}" "''${pending_dsts[$i]}"
      done

      rm -rf -- \
        "$config_dir/plugins/migrated-settings" \
        "$HOME/.gemini/antigravity/plugin_data/migrated-settings" \
        "$cli_dir/plugin_data/migrated-settings"
      if [ "$had_migrated" -eq 1 ]; then
        rm -f -- "$config_dir/mcp_config.json.backup"
      fi

      echo "Antigravity: configuration updated"
    '';
  };

  installPluginsEnabled = cliEnabled && agyPkg != null && marketplacePlugins != [ ];
  agyBin = lib.getExe agyPkg;
  cliArg = if cliSettingsFile != null then "${cliSettingsFile}" else "";
  hubArg = if hubStorageFile != null then "${hubStorageFile}" else "";
  xdgConfigArg = if xdgConfigHome != null then xdgConfigHome else "";
in
{
  inherit applyConfig;

  activation =
    lib.optionalAttrs installPluginsEnabled {
      installAntigravityPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        export PATH="${
          lib.makeBinPath [
            pkgs.git
            pkgs.jq
          ]
        }:$PATH"
        run ${lib.getExe applyConfig} --check "" "" "" "" "" ${lib.escapeShellArg cliArg} ${lib.escapeShellArg hubArg} ${lib.escapeShellArg xdgConfigArg}

        missing_plugins=()
        ${lib.concatMapStringsSep "\n" (p: ''
          plugin_dir="$HOME/.gemini/config/plugins/${p.name}"
          if [ ! -d "$plugin_dir" ]; then
            missing_plugins+=(${lib.escapeShellArg p.ref})
          elif [ -s "$HOME/.gemini/config/config.json" ]; then
            actual_mp="$(jq -r --arg name ${lib.escapeShellArg p.name} '.plugins[$name].installedFrom.marketplace // ""' "$HOME/.gemini/config/config.json" 2>/dev/null || true)"
            if [ -n "$actual_mp" ] && [ "$actual_mp" != ${lib.escapeShellArg p.marketplace} ]; then
              echo "warning: installAntigravityPlugins: plugin '${p.name}' installed from '$actual_mp', expected '${p.marketplace}'" >&2
            fi
          fi
        '') marketplacePlugins}
        if [ "''${#missing_plugins[@]}" -gt 0 ]; then
          if ${pkgs.curl}/bin/curl --silent --show-error --fail --max-time 5 \
              --output /dev/null \
              https://www.gstatic.com/generate_204; then
            for plugin_ref in "''${missing_plugins[@]}"; do
              run ${agyBin} plugin install "$plugin_ref" \
                || echo "warning: installAntigravityPlugins: failed to install $plugin_ref" >&2
            done
          else
            echo "warning: installAntigravityPlugins: network probe failed, skipping plugin install for: ''${missing_plugins[*]}" >&2
          fi
        fi
      '';
    }
    // {
      antigravitySetup =
        lib.hm.dag.entryAfter
          ([ "writeBoundary" ] ++ lib.optional installPluginsEnabled "installAntigravityPlugins")
          ''
            run ${lib.getExe applyConfig} \
              ${mcpServersFile} \
              ${hooksFile} \
              ${pluginsFile} \
              ${permissionsFile} \
              ${stateFile} \
              ${lib.escapeShellArg cliArg} \
              ${lib.escapeShellArg hubArg} \
              ${lib.escapeShellArg xdgConfigArg}
          '';
    };
}
