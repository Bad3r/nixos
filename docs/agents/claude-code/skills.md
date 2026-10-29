# Claude Code Skills

`CLAUDE.md` carries persistent project context and conventions.
A skill carries a reusable workflow invoked for a specific task.

## Nix-managed skills

Define shared skills in `modules/agents/skills/` through the registry in `modules/agents/skills.nix`.
Keep shared instructions in the skill body and client-specific frontmatter in its Codex or Claude profile.
Use an existing definition in that directory as the source format.

Installation wiring belongs in `modules/agents/claude-code/home.nix` and `modules/agents/codex/home.nix`.
Change the declarative source rather than generated files under the user's skill directories.
Source validation does not activate a Home Manager generation.

[Skill Providers](skill-providers.md) covers standalone, bundled, plugin, and account-synced skill ownership and availability.

## Project skills

Keep repository-specific workflows with the repository:

```text
.claude/skills/<skill-name>/
  SKILL.md
  references/
  scripts/
```

Add references or scripts only when the workflow needs them.
Keep the entry point focused and link supporting material so it loads when needed.
A skill should supply useful local knowledge, a concrete output contract, or tested automation.

The [Claude Code skills reference](https://code.claude.com/docs/en/skills) covers frontmatter, invocation, arguments, permissions, and supporting files.
