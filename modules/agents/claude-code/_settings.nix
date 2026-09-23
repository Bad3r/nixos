/*
  Settings producer for Claude Code.

  Merges the static defaults from _default-settings.nix with runtime values
  (enabledPlugins, deniedMcpServers, skillOverrides, mcpServers) and produces:
    - claudeSettings: the value rendered to ~/.claude/settings.json.
    - claudeSettingsFile: the store-path JSON file consumed by the jq merge
      in _activation.nix.
    - claudeJsonConfig: the UI/MCP merge template for ~/.claude.json.
    - claudeJsonConfigFile: the store-path JSON file consumed by the jq merge
      in _activation.nix.

  Note: attribute order is irrelevant for builtins.toJSON, so re-adding
  enabledPlugins, deniedMcpServers, skillOverrides, and mcpServers via `//`
  produces JSON byte-identical to a monolithic attrset literal with `inherit`.

  Each merge asserts its injected key names exactly match
  defaults.injectedSettings/injectedClaudeJson, so a key added here without
  updating that list in _default-settings.nix fails evaluation instead of
  silently escaping the injectedButStatic and retiredSettingsButLive guards
  there.
*/
{
  lib,
  pkgs,
  defaults,
  enabledPlugins,
  mcpServers,
  deniedMcpServers ? [ ],
  skillOverrides ? { },
}:
let
  sorted = lib.sort builtins.lessThan;

  injectedSettingsValues = {
    inherit enabledPlugins skillOverrides;
    deniedMcpServers = map (serverName: { inherit serverName; }) deniedMcpServers;
  };
  injectedSettingsNames = sorted (builtins.attrNames injectedSettingsValues);
  declaredSettingsNames = sorted defaults.injectedSettings;
  claudeSettings =
    assert
      injectedSettingsNames == declaredSettingsNames
      || throw "modules/agents/claude-code/_settings.nix: injected settings keys ${builtins.toJSON injectedSettingsNames} do not match _default-settings.nix injectedSettings ${builtins.toJSON declaredSettingsNames}";
    defaults.claudeSettingsBase // injectedSettingsValues;

  claudeSettingsFile = pkgs.writeText "claude-settings.json" (builtins.toJSON claudeSettings);

  injectedClaudeJsonValues = {
    inherit mcpServers;
  };
  injectedClaudeJsonNames = sorted (builtins.attrNames injectedClaudeJsonValues);
  declaredClaudeJsonNames = sorted defaults.injectedClaudeJson;
  claudeJsonConfig =
    assert
      injectedClaudeJsonNames == declaredClaudeJsonNames
      || throw "modules/agents/claude-code/_settings.nix: injected claude.json keys ${builtins.toJSON injectedClaudeJsonNames} do not match _default-settings.nix injectedClaudeJson ${builtins.toJSON declaredClaudeJsonNames}";
    defaults.claudeJsonConfigBase // injectedClaudeJsonValues;

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
