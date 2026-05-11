/*
  Activation snippets for Claude Code.

  Produces:
    - claudeCodeSetup: idempotent jq merge into ~/.claude/settings.json and
      ~/.claude.json, preserving user keys while wholly replacing Nix-managed
      mcpServers entries. The Greptile plugin is toggled at activation time
      based on whether the SOPS-managed API key file is readable; the loop
      that follows patches every cached Greptile MCP config to delegate
      Authorization to the headers helper instead of relying on the
      `GREPTILE_API_KEY` env var.
    - installClaudeCodeViaBun: optional, only when
      programs.claude-code.extended.installMethods.bun.enable is true.

  The bun-related let bindings are intentionally lazy: when bunInstallEnabled
  is false, neither bunInstallDir nor bunBin is forced, so reading
  osConfig.programs.bun.extended.package is safe even on hosts where the bun
  options namespace is absent.
*/
{
  lib,
  pkgs,
  osConfig,
  config,
  claudeSettingsFile,
  claudeJsonConfigFile,
  greptilePluginKey,
  greptilePluginRequested,
  greptileApiKeyPath,
  greptileHeadersHelperPath,
}:
let
  bunInstallEnabled = lib.attrByPath [
    "programs"
    "claude-code"
    "extended"
    "installMethods"
    "bun"
    "enable"
  ] false osConfig;
  bunInstallDir = "${config.xdg.dataHome}/bun";
  bunBin = lib.getExe osConfig.programs.bun.extended.package;
  greptilePluginRequestedShell = if greptilePluginRequested then "1" else "0";
in
{
  claudeCodeSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    CLAUDE_SETTINGS="$HOME/.claude/settings.json"
    CLAUDE_SETTINGS_TMP="$(mktemp)"
    CLAUDE_CONFIG="$HOME/.claude.json"
    CLAUDE_CONFIG_TMP="$(mktemp)"
    GREPTILE_MCP_TMP=""
    trap 'rm -f "$CLAUDE_SETTINGS_TMP" "$CLAUDE_CONFIG_TMP" "$GREPTILE_MCP_TMP"' EXIT

    mkdir -p "$HOME/.claude"

    if [ -r "$CLAUDE_SETTINGS" ]; then
      existing_settings="$CLAUDE_SETTINGS"
    else
      existing_settings="${pkgs.writeText "empty-json.json" "{}"}"
    fi

    if [ "${greptilePluginRequestedShell}" = "1" ] && [ -r "${greptileApiKeyPath}" ] && [ -s "${greptileApiKeyPath}" ]; then
      greptile_enabled=true
    else
      greptile_enabled=false
    fi

    if ! ${pkgs.jq}/bin/jq \
      --slurpfile nixSettings ${claudeSettingsFile} \
      --arg plugin "${greptilePluginKey}" \
      --argjson greptileEnabled "$greptile_enabled" \
      '. as $existing
      | $nixSettings[0] as $nix
      | ($existing * $nix)
      | .enabledPlugins = (($existing.enabledPlugins // {}) + ($nix.enabledPlugins // {}))
      | .enabledPlugins[$plugin] = $greptileEnabled
      | .env = ((($existing.env // {}) + ($nix.env // {})) | del(.GREPTILE_API_KEY))' \
      "$existing_settings" > "$CLAUDE_SETTINGS_TMP"; then
      echo "ERROR: jq failed to merge Claude Code settings" >&2
      exit 1
    fi

    if ! ${pkgs.jq}/bin/jq empty "$CLAUDE_SETTINGS_TMP" 2>/dev/null; then
      echo "ERROR: resulting Claude Code settings are not valid JSON" >&2
      exit 1
    fi

    mv "$CLAUDE_SETTINGS_TMP" "$CLAUDE_SETTINGS"
    chmod 600 "$CLAUDE_SETTINGS"

    for greptile_mcp_config in \
      "$HOME"/.claude/plugins/cache/claude-plugins-official/greptile/*/.mcp.json \
      "$HOME"/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/greptile/.mcp.json
    do
      [ -f "$greptile_mcp_config" ] || continue
      GREPTILE_MCP_TMP="$(mktemp)"
      if ! ${pkgs.jq}/bin/jq --arg helper "${greptileHeadersHelperPath}" \
        '.greptile.headersHelper = $helper | del(.greptile.headers)' \
        "$greptile_mcp_config" > "$GREPTILE_MCP_TMP"; then
        echo "ERROR: jq failed to patch Greptile MCP config: $greptile_mcp_config" >&2
        exit 1
      fi
      mv "$GREPTILE_MCP_TMP" "$greptile_mcp_config"
      chmod 644 "$greptile_mcp_config"
    done

    # Ensure the file exists
    if [ ! -f "$CLAUDE_CONFIG" ]; then
      echo "{}" > "$CLAUDE_CONFIG"
    fi

    # Merge Nix-managed settings into existing config while replacing
    # Nix-managed MCP server entries wholesale to avoid stale per-server
    # keys like old command/args transport fallbacks lingering forever.
    if ! ${pkgs.jq}/bin/jq --slurpfile nixConfig ${claudeJsonConfigFile} \
      '. as $existing
      | $nixConfig[0] as $nix
      | ($existing * $nix)
      | .mcpServers = (($existing.mcpServers // {}) + ($nix.mcpServers // {}))' \
      "$CLAUDE_CONFIG" > "$CLAUDE_CONFIG_TMP"; then
      echo "ERROR: jq failed to merge config" >&2
      exit 1
    fi

    # Validate result is valid JSON
    if ! ${pkgs.jq}/bin/jq empty "$CLAUDE_CONFIG_TMP" 2>/dev/null; then
      echo "ERROR: resulting config is not valid JSON" >&2
      exit 1
    fi

    mv "$CLAUDE_CONFIG_TMP" "$CLAUDE_CONFIG"
    chmod 600 "$CLAUDE_CONFIG"

    echo "✢ Claude Code: config applied (MCP via agents.mcp)"
  '';
}
// lib.optionalAttrs bunInstallEnabled {
  # The probe URL is pinned to the public npm registry because every
  # host in this repo runs bun against the default registry. If a
  # future host points bun at a private mirror via `~/.bunfig.toml`
  # or `BUN_CONFIG_REGISTRY`, this probe will check the wrong
  # endpoint and either skip a working install or run an install
  # that fails immediately. Update the URL alongside the bun config
  # if that ever happens.
  installClaudeCodeViaBun = lib.hm.dag.entryAfter [ "writeBoundary" "createBunDir" ] ''
    export BUN_INSTALL="${bunInstallDir}"
    if ${pkgs.curl}/bin/curl --silent --show-error --fail --max-time 5 \
        --output /dev/null \
        https://registry.npmjs.org/@anthropic-ai/claude-code/latest; then
      run ${bunBin} install -g @anthropic-ai/claude-code
    elif [ -x "$BUN_INSTALL/bin/claude" ]; then
      echo "warning: installClaudeCodeViaBun: npm registry probe failed (see curl error above), keeping existing install at $BUN_INSTALL/bin/claude" >&2
    else
      echo "warning: installClaudeCodeViaBun: npm registry probe failed (see curl error above) and no existing claude-code binary at $BUN_INSTALL/bin/claude; rerun home-manager switch once the registry is reachable" >&2
    fi
  '';
}
