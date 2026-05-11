/*
  Activation snippets for Claude Code.

  Produces:
    - claudeCodeSetup: idempotent jq merge into ~/.claude.json, preserving
      user keys while wholly replacing Nix-managed mcpServers entries.
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
  claudeJsonConfigFile,
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
in
{
  # Configure Claude Code UI preferences and MCP servers in ~/.claude.json
  claudeCodeSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    CLAUDE_CONFIG="$HOME/.claude.json"
    TMP_FILE="$(mktemp)"
    trap 'rm -f "$TMP_FILE"' EXIT

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
      "$CLAUDE_CONFIG" > "$TMP_FILE"; then
      echo "ERROR: jq failed to merge config" >&2
      exit 1
    fi

    # Validate result is valid JSON
    if ! ${pkgs.jq}/bin/jq empty "$TMP_FILE" 2>/dev/null; then
      echo "ERROR: resulting config is not valid JSON" >&2
      exit 1
    fi

    mv "$TMP_FILE" "$CLAUDE_CONFIG"
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
