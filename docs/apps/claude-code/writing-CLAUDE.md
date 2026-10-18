# Writing CLAUDE.md

`CLAUDE.md` carries persistent, always-active instructions for agents working in
a repository or directory. Claude Code loads it into context at the start of
every session, so it competes for the same budget as the conversation itself:
every line must earn its place.

## What belongs in CLAUDE.md

- **Always-active rules**: conventions that apply to every interaction (coding
  style, ownership boundaries, safety constraints, validation expectations).
- **Non-obvious repository facts**: module-discovery rules, build commands,
  branch and PR workflow, where generated artifacts come from.
- **Pointers, not prose**: link to deeper docs (`docs/`) and import shared
  baseline files with `@path` when Claude Code should load them.

Put repeatable multi-step procedures (deploy checklists, migrations, review
workflows) in skills, not here. CLAUDE.md holds standing rules; skills hold
invocable processes. See [skills.md](skills.md) for that split.

## What to leave out

- Anything derivable from the code, git history, or generated output.
- One-off task notes or status that go stale.
- Long tutorials or reference material that belong in `docs/`.

## Style

- Short section headers with `##`.
- **Bold** for key terms.
- Terse, imperative language ("Run X", "Never do Y"), not narration.
- Simple bullet points over paragraphs.
- Write impersonally: name what the code, repo, or configuration does. Avoid
  first-person plural.

## Structure that works

1. A one-line statement of what the repository is.
2. Hard rules and safety constraints first (the things that must never be
   violated).
3. Architecture and ownership: where things live and who owns them.
4. Commands: how to build, format, test, and validate.
5. Workflow: branching, commits, PRs.

Keep each rule falsifiable. "Follow conventions" is noise; "Avoid literal path
imports; expose modules through namespace exports" is a rule an agent can apply.

## Layering

Claude Code loads `CLAUDE.md`, `CLAUDE.local.md`, and `.claude/rules/`; it does
not automatically load `AGENTS.md`. If `AGENTS.md` is the shared source of truth
for other agents, make `CLAUDE.md` import it with `@AGENTS.md` or symlink
`CLAUDE.md` to it, then add only Claude-specific deltas.

Keep shared conventions in one source of truth. Use deeper `CLAUDE.md` files or
path-scoped `.claude/rules/` only for narrow rules whose scope genuinely differs.
