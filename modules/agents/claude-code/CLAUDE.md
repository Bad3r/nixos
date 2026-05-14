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

Before reading any file, check its **size** and extension. Use structured tools to extract specific data.

**Search**: `rg -C 5 'pattern'`.

**Extract by format**:

- JSON: `jq`
- YAML/XML/TOML/CSV/INI/HCL: `yq` (use `-p` flag for non-YAML)
- HTML: `htmlq -f file.html '.selector'` (must use `-f` for file input)
- SQLite: `sqlite3`

**Workflow**:

1. Unknown location: use `rg` to find.
2. Known file, structured format: extract with `jq`/`yq`/etc.
3. Plain text: check `ls -lh` first. If >50KB, use `rg` to search. `head`/`tail`/`sed` are permitted for sampling fixed regions (file head, tail, line range) where `rg` is the wrong fit.

## Failure handling

Failures must surface, not swallow. Concretely: do not replace `raise`/`throw` with a no-op `pass`/`catch`, do not return placeholder data on exception, and do not add `--no-verify` or `|| true` to silence a failing step. If suppression is genuinely intended, log the cause first.

## Root cause fixes

Fix the producer of bad output, not downstream consumers. If the current codebase or the user Bad3r (`gh api user --jq .login`) controls the producer of a bad generated artifact, package, build output, API response, fixture, cache, lockfile, release asset, or similar output, repair that producer and add a regression check that would fail on the bad output. If the producer is external or cannot be changed in the current task, surface that constraint instead of masking it. Do not add compatibility shims, fallback paths, post-processing steps, or artifact rewrites unless the user explicitly approves a temporary mitigation. Label any mitigation as temporary, explain what blocks the source fix, and state the removal condition.

## Python

Use `uv` and `uvx` for all Python work. No `pip`, no `venv`, no direct `python` invocations. For inline or one-off dependencies, use `uv run --with <pkg> <script>`.

## Packages

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

- Stage only files you directly modified
- Use Conventional Commits: `type(scope): summary`
- Keep one logical concern per Commit
- Record validation commands used

**Body content**: Bodies must add information beyond the subject. Lead with the concrete reason. Answer at least one of:

- Which upstream version forces this.
- Which symptom this fixes.
- Which sibling package or symbol this is coupled to.

Cite version numbers, symbol names, error messages. Avoid adjectives like "compatible", "latest", "the line that...". Body wraps at 80 columns. Never open with "Update the X..." (the subject already says it).

## GitHub

**@mentions**: Never tag users unless directly asked or approved by user. Reason: an unsolicited @mention generates a notification and surprises the maintainer. Applies to PRs, issues, review comments, and commit trailers.

**PR/issue status**: When reporting completion or status of a PR or issue (background agent finished, merge done, push done, automated review verdict, etc.), include the full GitHub URL inline (`https://github.com/<owner>/<repo>/pull/<n>`). Apply to every PR/issue mention, not just the first.

## Source Code & Documentations Local Mirrors

- Stylix
  - Path: `/data/git/nix-community-stylix`
  - Use when: Inspect source or apply local patches.
- Home Manager
  - Path: `/data/git/nix-community-home-manager`
  - Use when: Review module behavior or backport fixes.
- Firefox source/docs
  - Path: `/data/git/mozilla-firefox-firefox`
  - Use when: Inspect Firefox source behavior, Gecko internals, or preferences.
- Firefox built docs
  - Path: `/data/git/mozilla-firefox-firefox-docs/current`
  - Use when: Browse generated Firefox source docs built by `git-mirror-firefox-docs.service`.
- MDN Web Docs
  - Path: `/data/git/mdn-content`
  - Use when: Reference MDN Web/API documentation offline.
- Firefox policies
  - Path: `/data/git/mozilla-policy-templates`
  - Use when: Inspect supported Firefox managed-policy templates and schema.
- Enterprise admin reference
  - Path: `/data/git/mozilla-enterprise-admin-reference`
  - Use when: Check Firefox enterprise policy behavior and syntax documentation.
- LibreWolf settings
  - Path: `/data/git/codeberg-librewolf-settings`
  - Use when: Inspect upstream LibreWolf default settings and uBO assets.
- i3 Docs
  - Path: `/data/git/i3-i3.github.io`
  - Use when: Reference i3 documentation offline.
- Duplicati Docs
  - Path: `/data/git/duplicati-documentation`
  - Use when: Look up `duplicati-cli` commands, options, or backup format.
- nixpkgs
  - Path: `/data/git/NixOS-nixpkgs`
  - Use when: Inspect/patch upstream expressions.
- nixos-hardware
  - Path: `/data/git/NixOS-nixos-hardware`
  - Use when: Pull hardware profiles and troubleshoot host hardware options.
- nixvim
  - Path: `/data/git/nix-community-nixvim`
  - Use when: Examine NixVim modules and options.
- treefmt-nix
  - Path: `/data/git/numtide-treefmt-nix`
  - Use when: Adjust formatter behavior or pinning.
- git-hooks.nix
  - Path: `/data/git/cachix-git-hooks.nix`
  - Use when: Update hook definitions or debug pre-commit failures.
- sops-nix
  - Path: `/data/git/Mic92-sops-nix`
  - Use when: Manage encrypted secret integrations.
- import-tree
  - Path: `/data/git/vic-import-tree`
  - Use when: Review/extend auto-loading behavior.
- files module
  - Path: `/data/git/mightyiam-files`
  - Use when: Update generated NixOS artifact sources (e.g., `.gitignore`).
