# Skills Technical Manual

Skills are Markdown files with YAML frontmatter that extend Claude Code with custom slash commands and guided workflows. They follow the open [Agent Skills](https://agentskills.io) format with Claude Code-specific extensions.

A skill encodes a repeatable multi-step process -- a deployment checklist, a code review workflow, a migration procedure -- into a single invocable unit. Skills enforce conventions, chain workflows through handoffs, and carry reference material that loads on demand rather than permanently occupying context.

Claude Code discovers skills at session start by scanning `.claude/skills/` directories. Each skill's description is indexed for semantic matching against user intent. When invoked, the full skill body is injected into the conversation context with string substitutions applied.

## Skill Directory Format

Each skill lives in its own directory containing a required `SKILL.md` entry point and optional co-located assets:

```
.claude/skills/my-skill/
├── SKILL.md           # Required entry point
├── reference.md       # Supporting documentation
├── examples/          # Usage examples
│   └── basic.md
└── scripts/
    └── helper.sh      # Executable utilities
```

Reference files load on demand when the skill body links to them, keeping the main skill focused on instructions.

## Invocation Methods

Skills support three invocation pathways. Each pathway determines who initiates and how arguments reach the skill.

| Method          | Trigger                              | User Control                                                  |
| --------------- | ------------------------------------ | ------------------------------------------------------------- |
| Slash command   | User types `/skill-name [arguments]` | Direct; arguments captured as `$ARGUMENTS`                    |
| Skill tool      | Claude dispatches programmatically   | Controlled by permission rules and `disable-model-invocation` |
| Model-initiated | Description matches user intent      | Controlled by `disable-model-invocation`; transparent to user |

### Slash Commands

The primary invocation method. The user types `/skill-name` optionally followed by arguments:

```
/fix-issue 123
/migrate-component SearchBar React Vue
```

Arguments are captured as `$ARGUMENTS` (full string) or accessed by index (`$0`, `$1`, `$ARGUMENTS[0]`). Skills appear in tab completion when `user-invocable` is `true` (the default), showing the `argument-hint` if configured.

### Skill Tool (Programmatic)

Claude Code exposes an internal `Skill` tool that Claude can call programmatically. This enables skill chaining and handoff dispatching. The Skill tool respects permission rules: `Skill(name)` for exact match, `Skill(name *)` for prefix matching.

### Model-Initiated

When `disable-model-invocation` is `false` (the default), Claude reads skill descriptions from context and automatically loads matching skills when the user's request aligns with a description. This is transparent to the user -- Claude determines relevance and loads the full skill content without explicit invocation.

Set `disable-model-invocation: true` to restrict a skill to manual `/slash-command` invocation only.

## Definition and Structure

### File Format

A skill is defined by a `SKILL.md` file containing YAML frontmatter between `---` markers followed by a Markdown body:

```markdown
---
name: deploy-staging
description: Deploy the application to the staging environment
argument-hint: [branch-name]
allowed-tools: Bash, Read, Grep
---

# Deploy to Staging

Deploy branch `$0` to the staging environment.

## Steps

1. Verify branch exists and is up to date
2. Run test suite
3. Build artifacts
4. Deploy to staging
5. Verify deployment health
```

### Directory Layout

Skills are discovered from four locations, listed by scope:

```
# Enterprise (highest priority)
<managed-settings>/skills/<name>/SKILL.md

# Project (committed to version control)
<repo>/.claude/skills/<name>/SKILL.md

# Personal (user-wide)
~/.claude/skills/<name>/SKILL.md

# Plugin (namespaced as plugin-name:skill-name)
<plugin>/skills/<name>/SKILL.md
```

In monorepos, skills in nested `.claude/skills/` directories (e.g., `packages/frontend/.claude/skills/`) are automatically discovered when editing files in that package.

### Frontmatter Fields Reference

All fields are optional. When omitted, defaults apply as shown.

| Field                      | Type    | Default           | Description                                                                                  |
| -------------------------- | ------- | ----------------- | -------------------------------------------------------------------------------------------- |
| `name`                     | string  | Directory name    | Display name and slash command identifier. Lowercase, hyphens, max 64 characters             |
| `description`              | string  | First paragraph   | What the skill does and when to use it. Used for model-initiated matching                    |
| `argument-hint`            | string  | (none)            | Autocomplete hint shown after `/name`. Example: `[issue-number]`                             |
| `disable-model-invocation` | boolean | `false`           | When `true`, prevents Claude from auto-loading this skill. Manual `/name` only               |
| `user-invocable`           | boolean | `true`            | When `false`, hides from `/` menu. Skill remains available as background knowledge           |
| `allowed-tools`            | string  | (inherit all)     | Comma-separated tool whitelist for implicit permission. Example: `Read, Grep, Glob`          |
| `model`                    | string  | (inherit)         | Override model for this skill: `sonnet`, `opus`, `haiku`, or `inherit`                       |
| `context`                  | string  | (inline)          | Set to `fork` to run in an isolated subagent context                                         |
| `agent`                    | string  | `general-purpose` | Subagent type when `context: fork`. Options: `Explore`, `Plan`, `general-purpose`, or custom |
| `hooks`                    | object  | (none)            | Lifecycle hooks scoped to skill execution. Supports `PreToolUse`, `PostToolUse`, `Stop`      |
| `handoffs`                 | array   | (none)            | Follow-up actions presented on skill completion                                              |

### String Substitutions

Substitutions are processed in the Markdown body before injection into context.

| Variable               | Description                               | Example Value                 |
| ---------------------- | ----------------------------------------- | ----------------------------- |
| `$ARGUMENTS`           | Full argument string passed at invocation | `SearchBar React Vue`         |
| `$ARGUMENTS[N]`        | Nth argument by zero-based index          | `$ARGUMENTS[0]` → `SearchBar` |
| `$N`                   | Shorthand for `$ARGUMENTS[N]`             | `$0` → `SearchBar`            |
| `${CLAUDE_SESSION_ID}` | Current session identifier                | `abc123`                      |

When a skill body does not contain `$ARGUMENTS`, Claude Code appends `ARGUMENTS: <value>` to the end of the injected content automatically.

### Body Format

The Markdown body contains the instructions Claude follows when the skill is invoked. Effective bodies follow a consistent structure:

- **Goal section**: state the objective clearly at the top
- **Numbered steps**: ordered procedure Claude should follow
- **Constraints**: rules or boundaries (what not to do, required tools, output format)
- **Output format**: expected deliverable structure

Use standard Markdown: headers, lists, code blocks, bold for emphasis. Claude reads the body as instructions, so write in imperative form.

### Annotated Example

```yaml
---
# Identity: lowercase, hyphens, becomes /review-pr command
name: review-pr

# Indexed at session start; drives model-initiated matching.
# Keep under ~200 chars to leave budget for other skills.
description: >
  Review a pull request for code quality, security issues,
  and adherence to project conventions.

# Shows in autocomplete: /review-pr [pr-number]
argument-hint: [pr-number]

# Only invoke manually -- don't auto-trigger on vague queries
disable-model-invocation: true

# Grant implicit permission for these tools during execution
allowed-tools: Read, Grep, Glob, Bash

# Use a faster model for this routine task
model: sonnet
---

# Pull Request Review

Review PR #$0 following the checklist below.

## Context

- PR diff: !`gh pr diff $0`
- PR description: !`gh pr view $0 --json body --jq .body`

## Checklist

1. **Correctness**: verify logic matches PR description intent
2. **Security**: check for injection vectors, credential exposure, unsafe deserialization
3. **Tests**: confirm new code has test coverage
4. **Style**: verify naming conventions and formatting
5. **Dependencies**: flag new dependencies and license concerns

## Output

Provide a summary with:
- Overall assessment (approve / request changes)
- Specific findings with file paths and line numbers
- Suggested fixes as code blocks

Session: ${CLAUDE_SESSION_ID}
```

## Execution Lifecycle

### Discovery

At session start, Claude Code scans all skill locations (enterprise, project, personal, plugin) for `*/SKILL.md` files. For each skill discovered:

1. Frontmatter is parsed for `name`, `description`, `user-invocable`, `argument-hint`
2. Descriptions are loaded into a semantic index (budget: ~15,000 characters across all skills)
3. Full Markdown bodies are **not** loaded until invocation

If the combined description length exceeds the budget, lower-priority skills are excluded. Check with the `/context` command. The budget is configurable via `SLASH_COMMAND_TOOL_CHAR_BUDGET`.

### Resolution

When multiple skills share the same name, scope determines precedence:

1. **Enterprise** overrides all others
2. **Project** overrides personal and plugin
3. **Personal** overrides plugin
4. **Plugin** skills use `plugin-name:skill-name` namespacing and cannot conflict

### Injection and Execution

When a skill is invoked:

1. Full `SKILL.md` content is read from disk
2. Dynamic context preprocessor runs: `` !`command` `` placeholders execute as shell commands, output replaces the placeholder
3. String substitutions are applied (`$ARGUMENTS`, `$0`, `${CLAUDE_SESSION_ID}`)
4. `allowed-tools` restrictions take effect
5. Processed content is injected as system context
6. Hooks fire according to their lifecycle events (`PreToolUse`, `PostToolUse`, `Stop`)

For `context: fork` skills, the processed content becomes the subagent's prompt in an isolated context (no conversation history).

### Completion and Handoffs

When a skill finishes execution:

- If `handoffs` are configured, follow-up buttons are presented to the user
- If a handoff has `send: true`, it auto-dispatches without user interaction
- Skill-scoped hooks are cleaned up

## Skills vs Tools

| Aspect        | Skills                                        | Tools (MCP / Built-in)                       |
| ------------- | --------------------------------------------- | -------------------------------------------- |
| Definition    | Markdown files with YAML frontmatter          | Code implementing a tool interface           |
| Invocation    | `/slash-command`, Skill tool, or auto-match   | Model-initiated only                         |
| Scope         | Enterprise, project, personal, plugin         | Global (built-in) or MCP server scope        |
| State         | Shares conversation or forks isolated context | Stateless per-call                           |
| Composability | Chains via handoffs and Skill tool dispatch   | Direct tool calls                            |
| Authoring     | Markdown -- no code required                  | Code in supported languages                  |
| Customization | Full control over instructions and behavior   | Limited to parameters defined by tool schema |

Skills define _what to do_ (orchestration and process). Tools define _how to do it_ (capability and execution). A skill typically invokes tools as part of its procedure.

## Context Interaction

### Prompt Injection

The skill body, after substitutions and preprocessing, is injected as a system instruction into the conversation. Claude treats it as authoritative guidance for the current task.

### Description Budget

All enabled skill descriptions share a budget of ~15,000 characters at session start. This budget covers the semantic index that enables model-initiated invocation. If exceeded:

- Lower-priority skills (by scope) are excluded from the index
- The `/context` command reports which skills are loaded
- Override with `SLASH_COMMAND_TOOL_CHAR_BUDGET=<chars>` environment variable

Keep individual descriptions concise (under ~200 characters) to leave room for other skills.

### Context Modes

| Mode   | Field Value     | Execution                | Context Access                 | Use Case                                      |
| ------ | --------------- | ------------------------ | ------------------------------ | --------------------------------------------- |
| Inline | (default)       | Main conversation thread | Full conversation history      | Guidelines, reference knowledge, inline steps |
| Fork   | `context: fork` | Isolated subagent        | Only skill content + CLAUDE.md | Self-contained tasks, research, analysis      |

Fork mode requires the `agent` field to specify the subagent type:

- `Explore` -- read-only tools, optimized for searching
- `Plan` -- read-only tools, designed for research and planning
- `general-purpose` -- all tools (default)
- Custom agent name from `.claude/agents/`

### Dynamic Context Injection

The `` !`command` `` syntax runs shell commands as a preprocessing step before the skill body reaches Claude:

```markdown
## Current State

- Branch: !`git branch --show-current`
- Status: !`git status --short`
- Recent commits: !`git log --oneline -5`
```

Each `` !`command` `` executes immediately at load time. The command output replaces the placeholder in the skill body. Claude receives the fully-rendered content -- it does not execute these commands itself.

This enables skills to inject live data (git state, API responses, file contents) without consuming a tool call.

## Best Practices

### When to Use Skills

Use skills for **repeatable multi-step workflows** that benefit from consistent execution. Use `CLAUDE.md` for **persistent rules** that apply to every interaction.

| Use Case                           | Mechanism |
| ---------------------------------- | --------- |
| Deployment checklist               | Skill     |
| Code review procedure              | Skill     |
| Migration workflow                 | Skill     |
| Coding conventions (always active) | CLAUDE.md |
| Repository structure rules         | CLAUDE.md |
| Safety guardrails                  | CLAUDE.md |

### Structuring Skill Bodies

Effective skills follow a predictable structure:

1. **Title and objective**: what this skill accomplishes
2. **User input**: where `$ARGUMENTS` and `$0`..`$N` are referenced
3. **Dynamic context**: `` !`command` `` blocks for live data
4. **Numbered steps**: the procedure to follow
5. **Constraints**: what not to do, required output format, tool restrictions
6. **Output format**: expected deliverable structure

Keep instructions specific and actionable. Avoid vague guidance like "review carefully" -- instead specify what to check and what constitutes a finding.

### Handoff Chains

Skills can compose into multi-stage workflows through handoffs. Each handoff presents a follow-up action on completion:

```yaml
---
name: feature-workflow
description: Guide a feature from spec to implementation
handoffs:
  - label: "Write spec"
    agent: specify
    prompt: "Create specification for $ARGUMENTS"
  - label: "Generate tasks"
    agent: tasks
    prompt: "Generate tasks from the spec"
    send: true # Auto-dispatch without user interaction
---
```

Design handoff chains so each stage is independently useful. A user should be able to stop after any stage and have a meaningful deliverable.

### Common Patterns

**Argument validation**: check arguments before proceeding.

```markdown
If `$0` is empty, ask the user to provide a target directory
before proceeding with the analysis.
```

**Script integration**: delegate complex logic to co-located scripts.

```markdown
Run the analysis script:
`./scripts/analyze.sh $0`

Then review the output and summarize findings.
```

**Progressive disclosure**: start with a summary, drill down on request.

```markdown
1. Produce a one-paragraph summary of findings
2. List specific issues with file paths and line numbers
3. If the user asks for details on any finding, provide
   the full analysis with code examples
```

**Read-only constraints**: prevent modifications when reviewing.

```yaml
---
allowed-tools: Read, Grep, Glob
---
```

## Technical Implementation

### Loading and Scanning

At session start, Claude Code walks each skill location directory, looking for `*/SKILL.md` files. Co-located assets (reference docs, scripts, examples) are not loaded during scanning -- they are fetched on demand when the skill body references them.

The scan order follows scope precedence, building a name-to-file mapping. Later scopes cannot override higher-priority scopes.

### Scope Hierarchy

| Scope      | Location                                | Precedence | Shared With               |
| ---------- | --------------------------------------- | ---------- | ------------------------- |
| Enterprise | Managed settings path                   | Highest    | Organization-wide         |
| Project    | `<repo>/.claude/skills/<name>/SKILL.md` | High       | All project collaborators |
| Personal   | `~/.claude/skills/<name>/SKILL.md`      | Medium     | User only                 |
| Plugin     | `<plugin>/skills/<name>/SKILL.md`       | Lowest     | Plugin users              |

Plugin skills are automatically namespaced as `plugin-name:skill-name` to avoid collisions.

### Description Indexing

Descriptions form a semantic index consulted for model-initiated invocation. The index is built once at session start and not refreshed mid-session. Adding or modifying skills requires restarting the session for changes to take effect.

The ~15,000 character budget is an approximate figure. Monitor usage with `/context` and adjust with `SLASH_COMMAND_TOOL_CHAR_BUDGET` if needed.

## CLI Integration

### CLI Flags

| Flag                                  | Effect                                              |
| ------------------------------------- | --------------------------------------------------- |
| `--disable-slash-commands`            | Disable all slash command invocation                |
| `--disallowedTools "Skill(name)"`     | Block a specific skill from programmatic invocation |
| `--disallowedTools "Skill(prefix *)"` | Block skills matching a prefix pattern              |

### Discovery and Autocomplete

- Typing `/` lists all user-invocable skills with descriptions
- Tab completion shows `argument-hint` values
- Built-in commands (`/help`, `/compact`, `/context`) are not skills and cannot be overridden

### Settings Configuration

Skill permissions are managed in `.claude/settings.json` or `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": ["Skill(commit)", "Skill(review *)"],
    "deny": ["Skill(deploy *)"]
  }
}
```

Permission patterns:

- `Skill` -- matches all skills
- `Skill(name)` -- matches exact skill name
- `Skill(prefix *)` -- matches skills starting with prefix

## Advanced Features

### Namespacing

Use dot-separated names to group related skills:

```yaml
---
name: db.migrate
---
```

```yaml
---
name: db.seed
---
```

```yaml
---
name: db.backup
---
```

These appear grouped in the `/` listing as `db.migrate`, `db.seed`, `db.backup`. Plugin skills are automatically namespaced with a colon separator: `plugin-name:skill-name`.

### Handoff Configuration

Handoffs define follow-up actions presented when a skill completes.

| Field    | Type    | Required | Description                                                     |
| -------- | ------- | -------- | --------------------------------------------------------------- |
| `label`  | string  | Yes      | Button text shown to user                                       |
| `agent`  | string  | Yes      | Target skill or agent name                                      |
| `prompt` | string  | No       | Prompt passed to the target. Supports `$ARGUMENTS` substitution |
| `send`   | boolean | No       | When `true`, auto-dispatches without waiting for user click     |

Example with chained handoffs:

```yaml
---
name: feature-spec
description: Write a feature specification
handoffs:
  - label: "Generate implementation plan"
    agent: plan
    prompt: "Plan implementation based on the spec just created"
  - label: "Create tasks from spec"
    agent: tasks
    prompt: "Generate tasks from the spec"
---
```

### Hook Integration

Skills can define lifecycle hooks scoped to their execution. Hooks use the same format as `settings.json` hooks:

```yaml
---
name: safe-deploy
description: Deploy with safety checks
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-command.sh"
  PostToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "./scripts/run-linter.sh"
  Stop:
    - hooks:
        - type: command
          command: "./scripts/cleanup.sh"
---
```

Supported hook events:

| Event         | Fires When                        |
| ------------- | --------------------------------- |
| `PreToolUse`  | Before a tool executes            |
| `PostToolUse` | After a tool completes            |
| `Stop`        | When the skill finishes execution |

Hooks are automatically scoped to the skill's lifecycle and cleaned up on completion. The `matcher` field accepts tool name patterns (pipe-separated for multiple: `"Edit|Write"`).

### Dynamic Context Injection

The `` !`command` `` preprocessor runs shell commands at skill load time, replacing placeholders with live output:

```markdown
## Environment

- Node version: !`node --version`
- Current branch: !`git branch --show-current`
- Pending changes: !`git diff --stat`
```

This is preprocessing, not runtime execution. Commands run once when the skill loads. Use this for injecting state that Claude needs to see but should not execute itself.

### Subagent / Fork Mode

Setting `context: fork` runs the skill in an isolated subagent:

```yaml
---
name: deep-research
description: Research a topic thoroughly
context: fork
agent: Explore
---
Research $ARGUMENTS thoroughly. Find all relevant files,
read and analyze code, and summarize findings.
```

Fork mode characteristics:

- Isolated context: no conversation history, only skill content and CLAUDE.md
- Subagent type determines available tools and model
- Results are summarized and returned to the main conversation
- Useful for tasks that should not be influenced by prior context

### Tool Restrictions

The `allowed-tools` field grants implicit permission for listed tools during skill execution:

```yaml
---
allowed-tools: Read, Grep, Glob
---
```

This removes one permission barrier for the listed tools. However:

- Baseline permission settings from `/permissions` still apply
- If settings explicitly deny a tool, `allowed-tools` cannot override the denial
- Unlisted tools still require normal permission approval

Use this for read-only skills (grant `Read, Grep, Glob`) or skills that need specific tool access without prompting.

### Model Override

Route a skill to a specific model regardless of the session default:

```yaml
---
model: haiku
---
```

| Value     | Use Case                                 |
| --------- | ---------------------------------------- |
| `haiku`   | Fast, routine tasks (formatting, lookup) |
| `sonnet`  | Balanced tasks (review, analysis)        |
| `opus`    | Complex tasks (architecture, debugging)  |
| `inherit` | Use session default (same as omitting)   |

Model override applies only during skill execution. The session reverts to its default model after the skill completes.
