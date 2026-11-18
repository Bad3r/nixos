{
  lib,
  configDir,
  cacheHome,
  localMarketplace,
  enabledPlugins,
}:
{
  marketplaces = {
    openai-bundled = {
      source_type = "local";
      source = "${configDir}/.tmp/bundled-marketplaces/openai-bundled";
    };
    openai-primary-runtime = {
      source_type = "local";
      source = "${cacheHome}/codex-runtimes/codex-primary-runtime/plugins/openai-primary-runtime";
    };
    nixos-local = {
      source_type = "local";
      source = toString localMarketplace;
    };
    claude-plugins-official = {
      source_type = "git";
      source = "https://github.com/anthropics/claude-plugins-official.git";
    };
  };

  plugins = lib.mapAttrs (_: enabled: { inherit enabled; }) enabledPlugins;
}
