## Voice

In repo artifacts (issues, PRs, commit messages, code comments, docs), never use "we", "our", or "us". Write impersonally: name what the code, repo, or configuration does. Rewrite "we do X" as "X is done", "the repo does X", or name the subject directly. Template-provided "I"-attestations (e.g. PR-template checkboxes like "I have tested...") stay as-is.

## Punctuation

Never use em-dash `—` or en-dash `–` in any output: chat replies, commit messages, PR descriptions, code, docs, bash commands, file contents. Replace with one of:

- Period (hard stop)
- Comma (parenthetical clause)
- Colon (introducing a list or elaboration)
- Parentheses (asides)
- Plain hyphen `-` (compound words only)

## File Parsing & Search

Before reading any file, check its **size** and extension. Use structured tools to extract specific data. Never read entire structured files into context.

**Search**: `rg -C 5 'pattern'`. Never `grep`.

**Extract by format**:

- JSON: `jq`
- YAML/XML/TOML/CSV/INI/HCL: `yq` (use `-p` flag for non-YAML)
- HTML: `htmlq -f file.html '.selector'` (must use `-f` for file input)
- SQLite: `sqlite3`

**Workflow**:

1. Unknown location: use `rg` to find.
2. Known file, structured format: extract with `jq`/`yq`/etc.
3. Plain text: check `ls -lh` first. If >50KB, use `rg` to search. `head`/`tail`/`sed` are permitted for sampling fixed regions (file head, tail, line range) where `rg` is the wrong fit. This is an explicit carve-out from the harness's global preference for dedicated tools.

## Failure handling

Failures must surface, not swallow. Concretely: do not replace `raise`/`throw` with a no-op `pass`/`catch`, do not return placeholder data on exception, and do not add `--no-verify` or `|| true` to silence a failing step. If suppression is genuinely intended, log the cause first.

## Root cause fixes

Fix the producer of bad output, not downstream consumers. If the current codebase controls the producer of a bad generated artifact, package, build output, API response, fixture, cache, lockfile, release asset, or similar output, repair that producer and add a regression check that would fail on the bad output. If the producer is external or cannot be changed in the current task, surface that constraint instead of masking it. Do not add compatibility shims, fallback paths, post-processing steps, or artifact rewrites unless the user explicitly approves a temporary mitigation. Label any mitigation as temporary, explain what blocks the source fix, and state the removal condition.

## Python

Use `uv` and `uvx` for all Python work. No `pip`, no `venv`, no direct `python` invocations. For inline or one-off dependencies, use `uv run --with <pkg> <script>`.

## Nix

**Missing packages**: When a command is not installed, try `nix run nixpkgs#<pkg> -- <flags>` before asking the user to install. The nixpkgs attribute may differ from the binary name (e.g. `ripgrep` for `rg`); use `nix search nixpkgs <term>` to find it.

## Documentation

Update docs as part of any change that introduces:

- a new module, public API, CLI flag, env var, or config option
- behavior visible to callers (default, output format, exit code, side effect)
- a new external dependency or system requirement
- a non-obvious constraint or design tradeoff worth recording for future readers
- a workflow others must follow

Update existing locations (`docs/`, `README.md`, `CLAUDE.md`, `AGENTS.md`) rather than creating new files. Capture the _why_ only when a future reader would be surprised: hidden constraints, bug-specific workarounds, non-obvious tradeoffs.

Skip docs for: refactors without interface change, formatting/typo edits, test-only changes, dependency bumps without behavior change.

## Commits

**Body content**: Bodies must add information beyond the subject. Lead with the concrete reason. Answer at least one of:

- Which upstream version forces this.
- Which symptom this fixes.
- Which sibling package or symbol this is coupled to.

Cite version numbers, symbol names, error messages. Avoid adjectives like "compatible", "latest", "the line that...". Body wraps at 80 columns. Never open with "Update the X..." (the subject already says it).

**`/commit` skill invocation**: when the user types `/commit`, the harness invokes the skill directly. For fuzzy phrasings ("commit action", "commit this", "commit and push"), apply `~/.claude/skills/commit/SKILL.md` despite its `disable-model-invocation: true` flag. Worktree paths, branch slug inference, uniqueness gates, and `/commit` vs `/commit and push` mode rules live in that skill file; do not duplicate them here.

## GitHub

**@mentions**: Never tag users unless directly asked or approved by user. Reason: an unsolicited @mention generates a notification and surprises the maintainer. Applies to PRs, issues, review comments, and commit trailers.

**PR/issue status**: When reporting completion or status of a PR or issue (background agent finished, merge done, push done, automated review verdict, etc.), include the full GitHub URL inline (`https://github.com/<owner>/<repo>/pull/<n>`). Apply to every PR/issue mention, not just the first.
