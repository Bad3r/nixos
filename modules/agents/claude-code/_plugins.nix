# Plugin, marketplace, and skill keys for ~/.claude/settings.json. Uncomment
# a key and set its value to enable it. Every key set here replaces Claude's
# copy on each switch, and commenting it out again removes it, so /plugin and
# claude-plugins changes to enabledPlugins last only until the next switch.
{
  # Disable the skills and workflows that ship with Claude Code: bundled skills
  # and workflows are removed entirely; built-in slash commands stay typable but
  # are hidden from the model. Plugins, .claude/skills/, and .claude/commands/
  # are unaffected. Equivalent to CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1.
  disableBundledSkills = true;

  # Enabled plugins using plugin-id@marketplace-id format. Example: {
  # "formatter@anthropic-tools": true }. Also supports extended format with
  # version constraints. Settings precedence is user < project < local < flag
  # < policy, so to disable a plugin that project settings enable, set it to
  # false in .claude/settings.local.json - setting false in
  # ~/.claude/settings.json is overridden by the project.
  #
  # false keeps a plugin installed but disabled. The marketplace after `@` must
  # be registered: extraKnownMarketplaces below, or out of band.
  enabledPlugins = {
    "chrome-devtools-mcp@chrome-devtools-plugins" = true;
    "claude-code-setup@claude-plugins-official" = true;
    # Its bundled MCP server would duplicate the per-endpoint servers in
    # modules/agents/mcp/servers.nix.
    "cloudflare@cloudflare" = false;
    "code-review@claude-plugins-official" = true;
    "frontend-design@claude-plugins-official" = false;
    "pr-review-toolkit@claude-plugins-official" = false;
    # docs/drafts/chromium-webapps-plan-*.md need it; enable per task.
    "superpowers@claude-plugins-official" = false;
    "telemetry@builtin" = false;

    # Each enabled *-lsp entry also installs its language server
    # (lspPluginProgramMap in modules/apps/claude-code.nix).
    "clangd-lsp@claude-plugins-official" = true;
    "csharp-lsp@claude-plugins-official" = true;
    "gopls-lsp@claude-plugins-official" = true;
    "jdtls-lsp@claude-plugins-official" = true;
    "lua-lsp@claude-plugins-official" = true;
    "php-lsp@claude-plugins-official" = true;
    "pyright-lsp@claude-plugins-official" = true;
    "rust-analyzer-lsp@claude-plugins-official" = true;
    "swift-lsp@claude-plugins-official" = false;
    "typescript-lsp@claude-plugins-official" = true;
  };

  # Additional marketplaces to make available for this repository. Typically
  # used in repository .claude/settings.json to ensure team members have
  # required plugin sources.
  #
  # Registers the marketplaces enabledPlugins keys name, at
  # startup. claude-plugins-official installs out of band via `claude-plugins
  # install anthropics/claude-plugins-official`; builtin needs no registration.
  extraKnownMarketplaces."chrome-devtools-plugins".source = {
    source = "git";
    # Sparse: a full clone pulls a large submodule.
    url = "https://github.com/ChromeDevTools/chrome-devtools-mcp.git";
    sparsePaths = [ ".claude-plugin" ];
  };
  # cloudflare@cloudflare is disabled in enabledPlugins above. Enabling
  # it needs "skills" added to sparsePaths here, next to .claude-plugin
  # (docs/claude-code/skill-providers.md), or no sparsePaths for a full clone.
  #   extraKnownMarketplaces."cloudflare".source = {
  #     source = "git";
  #     url = "https://github.com/cloudflare/skills.git";
  #   };

  # User configuration values for MCP servers keyed by server name
  # pluginConfigs = { }; # [record]

  # Fraction of the context window (in characters) reserved for the skill
  # listing sent to Claude (default: 0.01 = 1%). When the listing exceeds this,
  # descriptions are shortened to fit. Raise to opt in to higher per-turn
  # context cost.
  # skillListingBudgetFraction = 0; # [number]

  # Per-skill description character cap in the skill listing sent to Claude
  # (default: 1536). Descriptions longer than this are truncated. Raise to opt
  # in to higher per-turn context cost.
  # skillListingMaxDescChars = 0; # [number]

  # Per-skill listing overrides keyed by skill name. "name-only" lists the
  # skill without its description; "user-invocable-only" hides it from the
  # model but keeps /name; "off" hides it from both. Absent = on.
  #
  # Keys are any installed skill name. Plugin skills follow their
  # enabledPlugins entry instead.
  skillOverrides = { };

  # Set to false to turn off syncing of plugins enabled on claude.ai; only
  # false is honored, since the sync feature itself is controlled server-side.
  # While on (the default when signed in), synced plugins re-sync each launch
  # and are removed when disabled on claude.ai (a same-named local plugin
  # still takes precedence). Not read from project settings
  # (.claude/settings.json). Since 2.1.280.
  syncClaudeAiPlugins = false;

  # Set to false to turn off syncing of skills enabled on claude.ai; only
  # false is honored, since the sync feature itself is controlled server-side.
  # While on (the default when signed in), synced skills re-sync every 10
  # minutes and are removed when disabled on claude.ai. Not read from project
  # settings (.claude/settings.json). Since 2.1.280.
  syncClaudeAiSkills = false;

  # --- Managed settings only: no effect in ~/.claude/settings.json ---

  # Managed-org allowlist of channel plugins. When set, replaces the default
  # Anthropic allowlist - admins decide which plugins may push inbound
  # messages. Undefined falls back to the default. Requires channelsEnabled:
  # true.
  # allowedChannelPlugins = [ ]; # [array]

  # Enterprise blocklist of marketplace sources. When set in managed settings,
  # these exact sources are blocked from being added as marketplaces. The
  # check happens BEFORE downloading, so blocked sources never touch the
  # filesystem.
  # blockedMarketplaces = [ ]; # [array]

  # Managed-org opt-in for channel notifications (MCP servers with the
  # claude/channel capability pushing inbound messages). claude.ai
  # Teams/Enterprise: default off. Console: default on unless managed settings
  # exist. Set true to allow; users then select servers via --channels.
  # channelsEnabled = true; # [boolean]

  # When true (and set in managed settings), rejects the --plugin-dir,
  # --plugin-url, --agents, and non-sdk --mcp-config CLI flags at startup.
  # Closes the CLI-flag bypass of strictKnownMarketplaces. Pair with
  # allowedMcpServers for per-server MCP control; this setting does not gate
  # other MCP entry points (SDK setMcpServers, claude mcp add, .mcp.json).
  # Also blocks surfaces that spawn the CLI with these flags internally (see
  # settings documentation). Only honored from managed settings; ignored in
  # user/project/local settings.
  # disableSideloadFlags = true; # [boolean]

  # Marketplace names whose plugins may surface as contextual install
  # suggestions (relevance-based tips). No marketplace-declared suggestions
  # surface without this allowlist; the built-in first-party frontend-design
  # tip is unaffected. Only honored when set in managed settings (policy
  # scope); the key is ignored in user, project, and local settings. A name
  # only takes effect when the marketplace is registered on the machine AND
  # its registered source is also declared in managed settings, either as the
  # extraKnownMarketplaces entry for that name or as an entry of
  # strictKnownMarketplaces. A marketplace registered from a different source
  # under an allowlisted name is ignored. The official marketplace is exempt
  # from the source requirement: allowlisting its name alone suffices, since
  # that name can only register from the official Anthropic source.
  # pluginSuggestionMarketplaces = [ ]; # [array]

  # Custom message to append to the plugin trust warning shown before
  # installation. Only read from policy settings (managed-settings.json /
  # MDM). Useful for enterprise administrators to add organization-specific
  # context (e.g., "All plugins from our internal marketplace are vetted and
  # approved.").
  # pluginTrustMessage = ""; # [string]

  # Enterprise strict list of allowed marketplace sources. When set in managed
  # settings, ONLY these exact sources can be added as marketplaces. The check
  # happens BEFORE downloading, so blocked sources never touch the filesystem.
  # Note: this is a policy gate only - it does NOT register marketplaces. To
  # pre-register allowed marketplaces for users, also set
  # extraKnownMarketplaces.
  # strictKnownMarketplaces = [ ]; # [array]

  # (Managed settings only) Block skills, agents, hooks, and MCP servers from
  # user and project sources, so they can only come from plugins or managed
  # settings. `true` locks all four surfaces; an array locks only the named
  # ones.
  # strictPluginOnlyCustomization = true; # [boolean | array]
}
