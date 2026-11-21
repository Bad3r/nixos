# Open Code Review

`ocr` reviews Git changes with a deterministic pipeline around an LLM ([nixos.nix](../../../modules/apps/open-code-review/nixos.nix), [home.nix](../../../modules/apps/open-code-review/home.nix)).
It reviews on subscription usage in two modes.
Upstream docs: <https://open-codereview.ai/docs>

## Review modes

- Native: `ocr review` runs OCR's own agent on ChatGPT plan usage through the `chatgpt` provider.
  The `open-code-review` skill drives it from Claude Code or Codex.
- Delegation: `ocr delegate` prints the reviewable files and their rule checklists without an LLM call, and the coding agent performs the review with its own login.
  The `open-code-review-delegate` skill drives it, and it is the only mode that uses the Claude subscription.

Both skills come from the `ocr` package, so their text matches the installed CLI.

## Sign in with ChatGPT

Precondition: a ChatGPT plan that OpenAI admits to Sign in with ChatGPT.

```sh
ocr auth login
```

The browser flow stores its tokens under `~/.opencodereview/auth/chatgpt/`.
Verify with `ocr auth status`, then `ocr llm test`.
`ocr llm models` lists the models the account offers; the provider takes the first one unless `settings.providers.chatgpt.model` names another.

## Review a change

```sh
ocr review --from main
ocr delegate preview --from main
```

`--from <ref>` reviews the committed changes since the merge-base with that ref.
Without range flags both commands review the staged, unstaged, and untracked changes.
`ocr review` saves each session under `~/.opencodereview/sessions/`, and `ocr viewer` browses them.

`ocr review` prints progress and a report for a person; the skills pass `--audience agent`, which leaves only the summary for the agent to relay.
The settings trade depth for speed and plan usage: `--effort medium` or `--effort high` adds review rounds to one run.
`--concurrency` and `--max-tokens-budget` bound a run and exist only as flags.

## Configuration

`~/.opencodereview/config.json` is a store symlink rendered from `programs.open-code-review.extended.settings`, so `ocr config set` and the `ocr config` pickers fail with a read-only error.
Change the option instead.

With no provider configured, `ocr review` takes API credentials from `OCR_LLM_*`, then `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, and `ANTHROPIC_MODEL`, then `export ANTHROPIC_*` lines in the shell rc files.
A configured provider ends that search, so keep `settings.provider` set.

## Telemetry

OCR's only telemetry is an OpenTelemetry export that `telemetry.enabled` or `OCR_ENABLE_TELEMETRY=1` turns on.
The settings keep it off, and the wrapper unsets the variable because it overrides the settings.
The Nix package is the Go binary without the npm launcher, which is the part that checks the registry for updates.
Sign in with ChatGPT sends OpenAI a stable identifier for the installation, kept in `~/.opencodereview/auth/chatgpt/host.json`.

## Pull request reviews

[ocr-review.yml](../../../.github/workflows/ocr-review.yml) runs the delegation mode in CI: Claude Code reviews the pull request on the `CLAUDE_CODE_OAUTH_TOKEN` subscription token.
A trusted author comments `/ocr-review` on a pull request to run it again.
The ChatGPT sign-in stays off CI: its refresh token rotates on use, and OpenAI's terms limit it to one person's local use.
