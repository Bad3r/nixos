/*
  Activation snippets for Claude Code.

  Produces:
    - claudeCodeSetup: idempotent jq merge into ~/.claude/settings.json and
      ~/.claude.json, preserving user keys while deleting source-declared
      retired keys, invalid legacy environment values, and wholly replacing
      Nix-managed mcpServers and, per marketplace name, extraKnownMarketplaces
      entries (jq's recursive `*` never drops a subkey such as sparsePaths
      once written, so each declared marketplace is replaced wholesale
      instead of deep-merged). mcpServers is union-only at the entry level
      for the same reason as enabledPlugins (`claude mcp add`'s "user" scope
      writes directly into this key), so a server dropped from
      modules/agents/mcp/servers.nix keeps its ~/.claude.json entry until it
      is removed there by hand. extraKnownMarketplaces stays union-only at the
      entry level, like enabledPlugins: the CLI's own `/plugin marketplace
      add` writes directly into this key (userSettings scope by default), so
      a marketplace name dropped from claudeSettingsBase is not deleted from
      settings.json; remove it there by hand. skillOverrides entries for
      managed skill names are fully owned by Nix, so a name dropped from
      programs.claude-code.extended.skillOverrides while its skill stays
      registered clears rather than lingers; entries for unmanaged names,
      including a name whose skill left the registry first, are preserved
      (modules/apps/claude-code.nix's skillOverrides option documents the
      resulting one-way trap and its manual cleanup). Full ownership is
      safe here: unlike enabledPlugins and extraKnownMarketplaces, the CLI's
      interactive skill-override toggle (verified against 2.1.280) writes
      only to the localSettings scope (.claude/settings.local.json), never to
      the userSettings scope this activation manages. enabledPlugins and env
      need no explicit rule: both are flat maps (`{ "<plugin>@<marketplace>"
      = bool; }`, `{ <NAME> = string; }`) on both sides (_plugins.nix,
      _env.nix), always present in $nix (_settings.nix and claudeSettingsBase
      inject them unconditionally), so the ambient recursive `*` merge above
      already unions each per key, right side winning; that is also the
      union-only contract modules/apps/claude-code.nix's extraPlugins option
      documents for enabledPlugins (removing a plugin is a manual
      settings.json edit there). An explicit rule for either would be
      redundant when both sides are well-formed and strictly worse when
      `$existing`'s value is a corrupted non-object: `*` degrades to picking
      $nix, while `("str" // {}) + $nix.thing` hard-errors, aborting
      activation. The retired-key, legacy-env-value, and env-name deletions
      below still need their own pipeline stage, since nothing else performs
      them.
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
  claudeEnv,
  claudeDefaults,
  managedClaudeSkillNames,
}:
let
  retiredSettingsJq = lib.optionalString (claudeDefaults.retired.settings != [ ]) (
    " | "
    + lib.concatMapStringsSep " | " (
      name: "del(.[${builtins.toJSON name}])"
    ) claudeDefaults.retired.settings
  );
  retiredEnvJq = lib.optionalString (claudeEnv.stripped != [ ]) (
    " | "
    + lib.concatMapStringsSep " | " (name: "del(.env[${builtins.toJSON name}])") claudeEnv.stripped
  );
  legacyEnvValuesJq = lib.optionalString (claudeEnv.legacyEnvValues != { }) (
    " | "
    + lib.concatStringsSep " | " (
      lib.mapAttrsToList (
        name: value:
        "if .env[${builtins.toJSON name}] == ${builtins.toJSON value} then del(.env[${builtins.toJSON name}]) else . end"
      ) claudeEnv.legacyEnvValues
    )
  );
  retiredJsonJq = lib.optionalString (claudeDefaults.retired.claudeJson != [ ]) (
    " | "
    + lib.concatMapStringsSep " | " (
      name: "del(.[${builtins.toJSON name}])"
    ) claudeDefaults.retired.claudeJson
  );
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
  # The settings.json merge filter and its jq variable bindings, lifted out of
  # claudeCodeSetup's script so checks."claude-code/settings-merge"
  # (modules/agents/claude-code/home-manager.nix) can exercise the actual
  # production filter, invoked with its actual production arguments, against
  # a fixture instead of a hand-copied approximation of either that could
  # silently drift from it. settingsMergeJq references $managedSkills, so
  # settingsMergeJqArgs is the one source of truth for the flag that binds it;
  # a check that reconstructed its own --argjson instead would not catch a
  # rename on either side.
  settingsMergeJqArgs = [
    "--argjson"
    "managedSkills"
    (builtins.toJSON managedClaudeSkillNames)
  ];
  settingsMergeJq = ''
    . as $existing
    | $nixSettings[0] as $nix
    | ($existing * $nix)
    | .deniedMcpServers = ((($existing.deniedMcpServers // []) + ($nix.deniedMcpServers // [])) | unique)
    | .extraKnownMarketplaces = (($existing.extraKnownMarketplaces // {}) + ($nix.extraKnownMarketplaces // {}))
    | .skillOverrides = ((($existing.skillOverrides // {}) | with_entries(select(.key as $k | ($managedSkills | index($k)) | not))) + ($nix.skillOverrides // {}))${legacyEnvValuesJq}${retiredEnvJq}${retiredSettingsJq}
  '';
  # The ~/.claude.json merge filter, lifted the same way as settingsMergeJq
  # and for the same reason: its mcpServers rule (per-entry wholesale
  # replace, dropping stale command/args pairs a changed transport type
  # leaves behind) and retiredJsonJq (live: claudeDefaults.retired.claudeJson
  # is non-empty) are exactly the class of rule that shipped as a no-op once
  # already (16e377d9); checks."claude-code/claude-json-merge" exercises this
  # filter too, not a hand-copied approximation of it.
  claudeJsonMergeJq = ''
    . as $existing
    | $nixConfig[0] as $nix
    | ($existing * $nix)
    | .mcpServers = (($existing.mcpServers // {}) + ($nix.mcpServers // {}))${retiredJsonJq}
  '';
in
{
  inherit
    settingsMergeJq
    settingsMergeJqArgs
    claudeJsonMergeJq
    ;
  activation = {
    claudeCodeSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      CLAUDE_SETTINGS="$HOME/.claude/settings.json"
      CLAUDE_SETTINGS_TMP="$(mktemp)"
      CLAUDE_CONFIG="$HOME/.claude.json"
      CLAUDE_CONFIG_TMP="$(mktemp)"
      trap 'rm -f "$CLAUDE_SETTINGS_TMP" "$CLAUDE_CONFIG_TMP"' EXIT

      mkdir -p "$HOME/.claude"

      if [ -r "$CLAUDE_SETTINGS" ]; then
        existing_settings="$CLAUDE_SETTINGS"
      else
        existing_settings="${pkgs.writeText "empty-json.json" "{}"}"
      fi

      if ! ${pkgs.jq}/bin/jq \
        ${lib.escapeShellArgs settingsMergeJqArgs} \
        --slurpfile nixSettings ${claudeSettingsFile} \
        '${settingsMergeJq}' \
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

      # Ensure the file exists
      if [ ! -f "$CLAUDE_CONFIG" ]; then
        echo "{}" > "$CLAUDE_CONFIG"
      fi

      # Merge Nix-managed settings into existing config while replacing
      # Nix-managed MCP server entries wholesale to avoid stale per-server
      # keys like old command/args transport fallbacks lingering forever.
      if ! ${pkgs.jq}/bin/jq --slurpfile nixConfig ${claudeJsonConfigFile} \
        '${claudeJsonMergeJq}' \
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
  };
}
