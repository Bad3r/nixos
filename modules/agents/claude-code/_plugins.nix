/*
  enabledPlugins composition for Claude Code.

  Returns the `enabledPlugins` attrset consumed by ~/.claude/settings.json
  together with the Greptile gating metadata used by _activation.nix.

  Sources:
    1. LSP plugins derived from programs.claude-code.extended.lspPlugins
       (single source of truth for LSP-style plugins), keyed by
       "<plugin>@claude-plugins-official".
    2. Additional plugins from programs.claude-code.extended.extraPlugins,
       keyed by the "<plugin>@<marketplace>" identifier used by Claude Code's
       settings.json.

  Greptile gating:
    The Greptile plugin requires a runtime API key file. To avoid writing a
    settings.json that flips the plugin on before the key is ready, the
    static Nix-rendered value is forced to `false`; the activation script
    then re-enables it iff the SOPS-managed key file is readable at
    activation time. `greptilePluginRequested` is the host opt-in flag
    (true when extraPlugins lists greptile@claude-plugins-official).
*/
{ lib, osConfig }:
let
  greptilePluginKey = "greptile@claude-plugins-official";

  lspPlugins = lib.attrByPath [ "programs" "claude-code" "extended" "lspPlugins" ] { } osConfig;
  extraPlugins = lib.attrByPath [ "programs" "claude-code" "extended" "extraPlugins" ] { } osConfig;

  gatedExtraPlugins =
    extraPlugins
    // lib.optionalAttrs (builtins.hasAttr greptilePluginKey extraPlugins) {
      ${greptilePluginKey} = false;
    };

  enabledPlugins =
    (lib.mapAttrs' (
      pluginKey: enabled: lib.nameValuePair "${pluginKey}@claude-plugins-official" enabled
    ) lspPlugins)
    // gatedExtraPlugins;

  greptilePluginRequested = lib.attrByPath [
    "programs"
    "claude-code"
    "extended"
    "extraPlugins"
    greptilePluginKey
  ] false osConfig;
in
{
  inherit enabledPlugins greptilePluginKey greptilePluginRequested;
}
