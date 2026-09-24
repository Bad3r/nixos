# Claude Code Skill Providers

## Ownership

Standalone skills and plugin skills use different controls.

- Nix-authored standalone skills live in `modules/agents/skills/` and are installed under `~/.claude/skills/` by Home Manager.
- Plugin-owned skills stay in their plugin source.
  The plugin enablement entry controls the skills and any MCP servers bundled by that plugin.
- MCP servers in `modules/agents/mcp/servers.nix` remain independent unless a plugin manifest bundles the same provider.

The Cloudflare plugin is declared as `cloudflare@cloudflare` from the Cloudflare Skills marketplace, which is not registered by default (see below).
It bundles Cloudflare skills and its API MCP server, so the individual upstream skills are not copied into the Nix skill registry.
Its plugin entry is disabled by default.

## Default Availability

Claude Code's bundled skills and workflows are removed entirely by `disableBundledSkills`.
Its built-in slash commands, `/doctor` and `/checkup` included, stay typable but are hidden from the model.
Nix-managed standalone skills are enabled by default.
Account-synced skills and plugins are disabled in the Claude settings.

Hide a standalone skill through `skillOverrides` in `modules/agents/claude-code/_plugins.nix`:

```nix
skillOverrides.commit = "off";
```

A skill's own frontmatter, such as `commit`'s `disable-model-invocation`, is a separate control that `skillOverrides` does not override.

Plugin-owned skill bundles follow their `enabledPlugins` entry in the same file.
`skillOverrides` does not affect plugin-provided skills.

The `cloudflare` marketplace's `extraKnownMarketplaces` entry in `modules/agents/claude-code/_plugins.nix` is left as a commented template while `cloudflare@cloudflare` stays disabled, since a disabled plugin gains nothing from a registered marketplace and the entry can never be retracted once written.
Enabling `cloudflare@cloudflare` means uncommenting that entry with `sparsePaths` covering `skills` as well as `.claude-plugin`, or no `sparsePaths` at all for a full clone.
The `cloudflare/skills` repository keeps its skill bundle in a top-level `skills/` directory that a `.claude-plugin`-only sparse clone would exclude; only its MCP server manifest, a root-level file, would register.
This is a property of that repository's layout, not of sparse clones in general: `chrome-devtools-plugins` stays sparse to `.claude-plugin` because its plugin is MCP-only and fetched via `npx` at runtime, with nothing else needed from the clone.

Cloudflare's [Claude Code plugin](https://github.com/cloudflare/skills) documents the bundled skills and MCP server.
