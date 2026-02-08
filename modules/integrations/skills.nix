/*
  Shared Skill Rules Library

  This module provides flake.lib.skills with tool-agnostic rule sets
  that can be consumed by multiple AI coding tool integrations.

  Each consumer wraps these with its own tool-specific frontmatter and chrome:
    - modules/hm-apps/claude-code.nix → ~/.claude/skills/commit/SKILL.md
    - modules/hm-apps/codex.nix       → ~/.config/codex/skills/commit/SKILL.md
*/
_: {
  flake.lib.skills = {
    # ════════════════════════════════════════════════════════════════════════
    # Shared commit rules — tool-agnostic markdown
    # No frontmatter, no dynamic injection, no argument handling.
    # Each consumer wraps these with its own tool-specific chrome.
    # ════════════════════════════════════════════════════════════════════════
    commitRules = ''
      ## Safety Rules — Absolute Prohibitions

      These rules are **non-negotiable** and override all other instructions.

      ### Forbidden Commands — NEVER Execute

      - `git stash drop` or `git stash clear` — never delete stashes
      - `git reset --hard` — never without explicit user approval
      - `git clean -fd` — never execute
      - `git add -A` or `git add .` — never bulk-stage; stage specific files by name
      - `git push --force` to main or master — warn user and refuse
      - `--no-verify` or `--no-gpg-sign` flags — never skip hooks or signing
      - `rm` or `rm -rf` on any files — use `rip` instead for recoverable deletion

      ### After Pre-Commit Hook Failure

      When a pre-commit hook fails, the commit did **NOT** happen. Therefore:
      - **NEVER** use `--amend` after a hook failure — it would modify the PREVIOUS commit
      - Instead: fix the issue, re-stage files, and create a **NEW** commit
      - Only use `--amend` when the user explicitly requests amending

      ## Pre-Commit Checklist

      Before staging or committing, verify:

      1. **No secrets or credentials** in staged files:
         - `.env`, `.env.*` files
         - `credentials.json`, API keys, tokens
         - Private keys, certificates
         - If detected, warn the user and refuse to commit

      2. **No generated artefacts** unless their source module was updated:
         - `.actrc`, `.gitignore`, `.sops.yaml`, `README.md`
         - These are managed by the files module — edit source definitions instead

      3. **Formatting and hooks** — remind the user if not yet run:
         - `nix fmt` for formatting
         - `nix develop -c lefthook run pre-commit` for hooks

      ## Staging Rules

      - Stage **only** files directly modified for this concern
      - Prefer `git add <specific-file> ...` — list each file by name
      - **One commit = one logical concern**
        - Include all files needed for that concern, even across multiple directories
        - Separate unrelated concerns into separate commits (feature vs docs, moduleA vs moduleB)

      ## Commit Message Format

      Use **Conventional Commits**: `type(scope): summary`

      ### Types

      | Type       | When to use                                    |
      |------------|------------------------------------------------|
      | `feat`     | New feature                                    |
      | `fix`      | Bug fix                                        |
      | `docs`     | Documentation only                             |
      | `style`    | Formatting, whitespace (no logic change)       |
      | `refactor` | Code restructuring (no feature or fix)         |
      | `perf`     | Performance improvement                        |
      | `test`     | Adding or updating tests                       |
      | `chore`    | Build, tooling, dependency changes             |

      ### Scope

      - Use the primary module, directory, or domain affected
      - Examples: `apps`, `home`, `flake`, `system76`, `sops`, `scripts`

      ### Message Guidelines

      - Summarize the "why" not the "what" — the diff shows what changed
      - Keep the summary line concise (1-2 sentences)
      - Note affected hosts/modules when relevant
      - Record validation commands run during development

      ### Multi-line Messages

      Always use a HEREDOC to pass commit messages:

      ```bash
      git commit -m "$(cat <<'EOF'
      type(scope): summary line

      Optional body with additional context.
      EOF
      )"
      ```
    '';

    # ════════════════════════════════════════════════════════════════════════
    # Shared commit workflow — tool-agnostic steps
    # Consumers may prepend tool-specific argument handling or dynamic
    # context sections before interpolating this block.
    # ════════════════════════════════════════════════════════════════════════
    commitWorkflow = ''
      ## Workflow

      1. Run `git status` and `git diff --staged` to analyze staged changes
      2. If nothing is staged, analyze unstaged changes and ask the user which files to stage
      3. Draft a commit message following the format above
      4. Present the draft to the user for approval before committing
      5. After user approves, create the commit

      ### Post-Commit

      Run `git status` after committing to verify success and show the user the result.
    '';
  };
}
