# Omit a client to leave the plugin out of its generated config.
{
  "cc-plugin-you-should-know@builtin" = {
    claude-code = true;
  };
  "telemetry@builtin" = {
    claude-code = false;
  };
  # The shared MCP registry supplies DevTools with enforced privacy flags.
  "chrome-devtools-mcp@chrome-devtools-plugins" = {
    claude-code = false;
  };
  "clangd-lsp@claude-plugins-official" = {
    claude-code = true;
    codex = true;
    program = "clangd";
  };
  "claude-code-setup@claude-plugins-official" = {
    claude-code = true;
    codex = true;
  };
  # The shared MCP registry supplies Cloudflare API through codemode, and modules/agents/skills/packs.nix installs Cloudflare skills.
  "cloudflare@claude-plugins-official" = {
    claude-code = false;
    codex = false;
  };
  "code-review@claude-plugins-official" = {
    claude-code = true;
    codex = true;
  };
  "csharp-lsp@claude-plugins-official" = {
    claude-code = true;
    codex = true;
    program = "csharp-ls";
  };
  "frontend-design@claude-plugins-official" = {
    claude-code = false;
  };
  "gopls-lsp@claude-plugins-official" = {
    claude-code = true;
    codex = true;
    program = "gopls";
  };
  "jdtls-lsp@claude-plugins-official" = {
    claude-code = true;
    codex = true;
    program = "jdt-language-server";
  };
  "lua-lsp@claude-plugins-official" = {
    claude-code = true;
    codex = true;
    program = "lua-language-server";
  };
  "php-lsp@claude-plugins-official" = {
    claude-code = true;
    codex = true;
    program = "intelephense";
  };
  "pr-review-toolkit@claude-plugins-official" = {
    claude-code = true;
    codex = true;
  };
  "pyright-lsp@claude-plugins-official" = {
    claude-code = true;
    codex = true;
    program = "pyright";
  };
  "rust-analyzer-lsp@claude-plugins-official" = {
    claude-code = true;
    codex = true;
    program = "rust-analyzer";
  };
  "superpowers@claude-plugins-official" = {
    claude-code = false;
  };
  "swift-lsp@claude-plugins-official" = {
    claude-code = false;
    program = "sourcekit-lsp";
  };
  "typescript-lsp@claude-plugins-official" = {
    claude-code = true;
    codex = true;
    program = "typescript-language-server";
  };
  # Both local plugins use the Claude Code TypeScript hook API, so Codex has no
  # nixos-local marketplace.
  "browser-webfetch@nixos-local" = {
    claude-code = true;
    program = "browser-fetch";
    commandOption = "fetchCommand";
  };
  "kagi-websearch@nixos-local" = {
    claude-code = true;
    program = "kagi-search";
    commandOption = "searchCommand";
  };
  "browser@openai-bundled" = {
    codex = true;
  };
  "chrome@openai-bundled" = {
    codex = true;
  };
  "codex-app-tools@openai-bundled" = {
    codex = true;
  };
  "unified-computer-use@openai-bundled" = {
    codex = true;
  };
  "visualize@openai-bundled" = {
    codex = true;
  };
  "documents@openai-primary-runtime" = {
    codex = true;
  };
  "pdf@openai-primary-runtime" = {
    codex = true;
  };
  "presentations@openai-primary-runtime" = {
    codex = true;
  };
  "spreadsheets@openai-primary-runtime" = {
    codex = true;
  };
  "template-creator@openai-primary-runtime" = {
    codex = true;
  };
  "swarm@builtin" = {
    "antigravity-cli" = true;
  };
  "android-cli-plugin@antigravity-plugins-official" = {
    "antigravity-cli" = true;
  };
  "chrome-devtools-plugin@antigravity-plugins-official" = {
    "antigravity-cli" = true;
  };
  # Replaced by `cloudflare-api` in codemode and the declarative `cloudflare-skills` pack.
  "cloudflare@antigravity-plugins-partners" = {
    "antigravity-cli" = false;
  };
  "egm@antigravity-plugins-official" = {
    "antigravity-cli" = true;
  };
  # Explicitly disabled so activation writes `enabled: false` on existing installs.
  "gdrive@antigravity-plugins-official" = {
    "antigravity-cli" = false;
  };
  # The shared MCP registry supplies Google Developer Knowledge with API-key auth and opt-in enablement.
  "google-developer-knowledge@antigravity-plugins-official" = {
    "antigravity-cli" = false;
  };
  # Replaced by the declarative `modern-web-guidance` skill pack across all clients.
  "modern-web-guidance-plugin@antigravity-plugins-official" = {
    "antigravity-cli" = false;
  };
}
