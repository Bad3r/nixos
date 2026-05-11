/*
  enabledPlugins composition for Claude Code.

  Returns the `enabledPlugins` attrset consumed by ~/.claude/settings.json.

  Sources:
    1. LSP plugins derived from programs.claude-code.extended.lspPlugins
       (single source of truth for LSP-style plugins), keyed by
       "<plugin>@claude-plugins-official".
    2. Additional plugins from programs.claude-code.extended.extraPlugins,
       keyed by the "<plugin>@<marketplace>" identifier used by Claude Code's
       settings.json.
*/
{ lib, osConfig }:
let
  enabledPlugins =
    (lib.mapAttrs' (
      pluginKey: enabled: lib.nameValuePair "${pluginKey}@claude-plugins-official" enabled
    ) (lib.attrByPath [ "programs" "claude-code" "extended" "lspPlugins" ] { } osConfig))
    // (lib.attrByPath [ "programs" "claude-code" "extended" "extraPlugins" ] { } osConfig);
in
{
  inherit enabledPlugins;
}
