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
         - `nix develop -c pre-commit run --all-files --hook-stage manual` for hooks

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
    # Shared commit workflow — dual-mode commit path selection
    # Consumers may prepend tool-specific argument handling or dynamic
    # context sections before interpolating this block.
    # ════════════════════════════════════════════════════════════════════════
    commitWorkflow = ''
      ## Workflow

      ### Select Mode

      Choose exactly one mode before staging or committing:

      1. Read the current branch: `git rev-parse --abbrev-ref HEAD`
      2. Parse intent flags from the user request:
         - `push_required` when the user asks to push
         - `pr_required` when the user asks to open a pull request
         - `labels_required` when the user asks to apply labels
      3. Normalize flags:
         - If `push_required=true`, force `pr_required=true` and `labels_required=true`
         - If `pr_required=true`, force `labels_required=true`
      4. Select mode in this precedence order:
         - If current branch is `main` or `master`: **`worktree_atomic`**
         - Else if the user explicitly asks for a new branch/worktree: **`worktree_atomic`**
         - Else if the user explicitly asks to continue current/same branch: **`continue_current_branch`**
         - Else (non-main branch): **`continue_current_branch`**
      5. Ask one short clarifying question only if intent remains ambiguous after these rules.

      ### Shared Preflight (both modes)

      Run these checks before staging or committing:

      ```bash
      git status --short
      git diff --staged --stat
      git diff --stat
      git log --oneline -5
      ```

      If nothing is staged, inspect unstaged changes and propose exact file paths to stage.

      ### `continue_current_branch` Mode

      Use this mode to keep working on the active non-main branch.

      1. Refuse execution if current branch is `main` or `master`
      2. Stage only explicit file paths for one logical concern
      3. Draft a Conventional Commit message
      4. Present the draft for approval if no explicit message was provided
      5. Commit on the current branch
      6. If `push_required=true`, run `git push -u origin <current-branch>`
      7. If `pr_required=true`, run `gh pr create --fill --head <current-branch>`
      8. If `labels_required=true`, apply labels with `gh pr edit --add-label ...`

      ### `worktree_atomic` Mode

      Use this mode for protected branches or when the user asks for explicit branch/worktree isolation.

      1. Snapshot worktrees and refs before changes:
         - `git worktree list --porcelain`
         - `git for-each-ref --format='%(refname:short)' refs/heads refs/remotes`
      2. Resolve base branch in this order:
         - User-specified base
         - `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`
         - Fallback: `main`, then `master`
      3. Derive `repo_name` and create worktree under `~/trees/<repo_name>/`
      4. Choose a unique non-main branch name (append `-r2`, `-r3`, ... when needed)
      5. If the source checkout has local edits, create a transfer stash that includes staged, unstaged, and untracked files:
         - `git status --porcelain` (if empty, skip transfer steps)
         - `git stash push --include-untracked -m "worktree-atomic-transfer-<timestamp>"`
         - `transfer_stash="$(git rev-parse --verify refs/stash)"`
      6. Create a brand-new worktree and branch:
         - `git worktree add -b <new-branch> "$HOME/trees/<repo_name>/<worktree-name>" <base-branch>`
      7. Verify the new worktree did not exist in the pre-snapshot and now exists in post-snapshot
      8. If a transfer stash was created, apply it inside the new worktree with index state preserved:
         - `git -C "$HOME/trees/<repo_name>/<worktree-name>" stash apply --index "$transfer_stash"`
      9. Run preflight checks and commit inside the new worktree
      10. If `push_required=true`, push with upstream tracking
      11. If `pr_required=true`, create PR; if `labels_required=true`, apply labels
      12. Never run `git stash drop` or `git stash clear`; keep transfer stashes unless the user explicitly requests cleanup

      ### Post-Commit

      Run `git status --short` after committing and report:
      - active branch and worktree path
      - commit SHA
      - push/PR/labels results when requested
    '';
  };
}
