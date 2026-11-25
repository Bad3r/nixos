# Claude Code Skill Providers

## Ownership

Standalone skills and plugin skills use different controls.

- Nix-authored standalone skills live in `modules/agents/skills/` and are installed under `~/.claude/skills/` by Home Manager.
  A skill that sets `app` installs only on hosts where that app's row is on.
- Package-shipped skills stay in their package: the app's Home Manager module links them from the store, as [open-code-review](../../../modules/apps/open-code-review/home.nix) does.
- Plugin-owned skills stay in their plugin source.
  The plugin enablement entry controls the skills and any MCP servers bundled by that plugin.
- MCP servers in `modules/agents/mcp/servers.nix` remain independent unless a plugin manifest bundles the same provider.

The Cloudflare skills (`cloudflare-skills`) and Modern Web Guidance (`modern-web-guidance`) come from pinned flake inputs in `modules/agents/skills/packs.nix` and link into `~/.claude/skills/` alongside standalone skills (as well as Antigravity and Codex).
Because pack skills link directly into `~/.claude/skills/`, `skillOverrides` controls them the same way as standalone skills.
In `modules/agents/_plugins.nix`, the Cloudflare marketplace plugins stay disabled across all three clients and `modern-web-guidance-plugin` stays disabled on Antigravity, while `cloudflare-api` in `modules/agents/mcp/servers.nix` supplies the authenticated Cloudflare API MCP server through `codemode`.

## Default Availability

Claude Code's bundled skills and workflows load, since `disableBundledSkills` would also remove `/code-review` and its `/review` alias.
Nix-managed standalone skills are enabled by default.
Account-synced skills and plugins are disabled in the Claude settings.

Hide a standalone or bundled skill through `skillOverrides` in `modules/agents/claude-code/_plugins.nix`:

```nix
skillOverrides.sbx = "off";
```

A skill's `disable-model-invocation` frontmatter is a separate control that `skillOverrides` does not override.

Plugin-owned skill bundles follow `programs.claude-code.extended.plugins`, which defaults to the Claude Code selections in the [shared plugin catalog](../../../modules/agents/_plugins.nix).
`skillOverrides` does not affect plugin-provided skills.

`chrome-devtools-plugins` stays sparse to `.claude-plugin` because its plugin provides only an MCP server.
Use the shared MCP registry's wrapper to keep DevTools privacy options consistent across clients.

Cloudflare's [skills repository](https://github.com/cloudflare/skills) and [Modern Web Guidance](https://github.com/GoogleChrome/modern-web-guidance) document those bundled skills.
