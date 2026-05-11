/*
  Settings producer for Claude Code.

  Merges the static defaults from _default-settings.nix with runtime values
  (enabledPlugins, mcpServers) and produces:
    - claudeSettings: the value rendered to ~/.claude/settings.json.
    - claudeSettingsFile: the store-path JSON file consumed by the jq merge
      in _activation.nix.
    - claudeJsonConfig: the UI/MCP merge template for ~/.claude.json.
    - claudeJsonConfigFile: the store-path JSON file consumed by the jq merge
      in _activation.nix.

  Note: attribute order is irrelevant for builtins.toJSON, so re-adding
  enabledPlugins and mcpServers via `//` produces JSON byte-identical to a
  monolithic attrset literal with `inherit`.
*/
{
  pkgs,
  defaults,
  enabledPlugins,
  mcpServers,
}:
let
  claudeSettings = defaults.claudeSettingsBase // {
    inherit enabledPlugins;
  };

  claudeSettingsFile = pkgs.writeText "claude-settings.json" (builtins.toJSON claudeSettings);

  claudeJsonConfig = defaults.claudeJsonConfigBase // {
    inherit mcpServers;
  };

  claudeJsonConfigFile = pkgs.writeText "claude-json-config.json" (builtins.toJSON claudeJsonConfig);
in
{
  inherit
    claudeSettings
    claudeSettingsFile
    claudeJsonConfig
    claudeJsonConfigFile
    ;
}
