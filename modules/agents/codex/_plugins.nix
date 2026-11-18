{
  lib,
  configDir,
  cacheHome,
  localMarketplace,
}:
let
  pluginSettings =
    marketplace: enabled: names:
    lib.genAttrs (map (name: "${name}@${marketplace}") names) (_: {
      inherit enabled;
    });
in
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

  plugins =
    pluginSettings "openai-bundled" true [
      "browser"
      "chrome"
      "codex-app-tools"
      "unified-computer-use"
      "visualize"
    ]
    // pluginSettings "openai-primary-runtime" true [
      "documents"
      "pdf"
      "presentations"
      "spreadsheets"
      "template-creator"
    ]
    // pluginSettings "claude-plugins-official" true [
      "clangd-lsp"
      "claude-code-setup"
      "code-review"
      "csharp-lsp"
      "gopls-lsp"
      "jdtls-lsp"
      "lua-lsp"
      "php-lsp"
      "pr-review-toolkit"
      "pyright-lsp"
      "rust-analyzer-lsp"
      "typescript-lsp"
    ]
    # These plugins register TypeScript hooks through the Claude Code module API.
    // pluginSettings "nixos-local" false [
      "browser-webfetch"
      "kagi-websearch"
    ];
}
