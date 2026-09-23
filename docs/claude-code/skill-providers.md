# Claude Code Skill Providers

## Ownership

Standalone skills and plugin skills use different controls.

- Nix-authored standalone skills live in `modules/agents/skills/` and are installed under `~/.claude/skills/` by Home Manager.
- Plugin-owned skills stay in their plugin source.
  The plugin enablement entry controls the skills and any MCP servers bundled by that plugin.
- MCP servers in `modules/agents/mcp/servers.nix` remain independent unless a plugin manifest bundles the same provider.

The Cloudflare plugin is registered as `cloudflare@cloudflare` from the Cloudflare Skills marketplace.
It bundles Cloudflare skills and its API MCP server, so the individual upstream skills are not copied into the Nix skill registry.
Its plugin entry is disabled by default.

## Default Availability

Claude Code's bundled skills, `/doctor` and `/checkup` included, stay typable but hidden from the model.
Nix-managed standalone skills are enabled by default.
Account-synced skills and plugins are disabled in the Claude settings.

Hide a standalone skill through the `skillOverrides` option:

```nix
programs.claude-code.extended.skillOverrides.commit = "off";
```

Plugin-owned skill bundles are controlled through `programs.claude-code.extended.extraPlugins`.
`skillOverrides` does not affect plugin-provided skills.

Cloudflare's [Claude Code plugin](https://github.com/cloudflare/skills) documents the bundled skills and MCP server.
