# sbx for agents

With the `sbx` row on, Claude Code and Codex get the `sbx` skill from `modules/agents/skills/sbx.nix`, a system-prompt line, and an allow rule for `sbx`.
The Codex allow rule in `modules/agents/codex/_exec-policy.nix` also runs `sbx` outside bwrap, since the CLI writes its state directory and starts user units.

## MCP server

Both clients start `sbx-mcp`, the `sbx` entry in `modules/agents/mcp/servers.nix`, whose tools take a verb's flags as arguments and return its `--json` document.

- The screenshot tool also returns a PNG image content block for direct visual inspection, alongside the saved path and MIME type.
- Its optional `ocr` argument adds Tesseract output under `text`; image inspection needs no OCR.
- Codex names its thread in every tool call, so `--mine` matches sandboxes from the CLI and the MCP tools alike.
- Claude Code passes its session only when it starts the server, so after `/clear` the tools keep the old session until `/mcp` reconnects `sbx`.
- Under MCP, the checkout copy root and relative host paths follow the directory the client started in.

## Approval hooks

The PreToolUse hooks in `modules/agents/hooks/sbx-approval.nix` hold three calls for the user, on the Bash tool and on the MCP `create`, `run`, and `share_attach` tools:

- a sandbox with egress: a `--net` value other than `none`, `--net` with no value, or MCP `net` other than `none`;
- `share attach` of `shared`, or with a missing or non-literal tag, and MCP `share_attach` whose `share` is `shared` or not a string;
- any Bash call of `sbx-mcp`, an `sbx` verb that `xargs` could turn into `create`, `run`, or `share`, and those verbs with an unquoted expansion, brace, or glob before `--`, or an unquoted command or process substitution, which can add arguments.

Claude Code asks the user, even in auto mode.
Codex refuses, so the user runs the command: its hooks cannot ask, and its execpolicy prompts go to the auto reviewer.
The hook drops shell comments, splits the command into shell words, and reads only the options before the first `--`, so offline sandboxes, guest commands, and read-only shares pass.
A shell or `source` that reads its script from stdin, a pipe, `/dev/stdin`, or a process substitution fails closed when the call names `sbx` anywhere; a here-string or heredoc it reads is checked as a script instead.
Every word naming a shell counts, an unknown long shell option fails closed, and the argument of `env -S` or fish `-C` is checked as a script; a script operand of `-` or a path through `dev` or `proc` counts as stdin.
Every word whose basename is `sbx` or `workloads` may start the real command, as in `env A=/sbx sbx ...`, so the hook checks the words after each one; an argument path ending in `/sbx` can add a prompt, and so can an `sbx` call in a guest command after `--`.
It checks the body of every command or process substitution, quoted or not, and of every heredoc whose delimiter is unquoted, as a script of its own; single-quoted text and `<<'EOF'` bodies do not expand, so they pass unless a shell reads the heredoc.
Unparsable shell text that names `sbx`, scripts nested more than four levels deep that mention `sbx` or `workloads`, commands over 64 KiB, and an unreadable tool call fail closed.

## Limits of the hooks

The hooks are a guard rail against a prompt-injected agent on the usual paths, not a security boundary.
Agents run as the owner's uid, so they can drive libvirt, `qemu-bridge-helper`, or the egress bridge directly.
These paths pass the hooks:

- a command built at runtime, such as `s=sbx; $s ...`, `$(command -v sbx) ...`, an unquoted expansion that splits into options, a script file, or an interpreter such as `python3` calling `sbx`;
- a script string handed to a runner other than a `-c` flag or `eval`, such as `ssh` or `watch`;
- Codex `write_stdin` into an open shell session, which runs no PreToolUse hook; the session's shell runs inside bwrap, where `sbx` cannot write `~/.local/share/sbx`, unless the auto reviewer approves running it outside;
- command tools other than Bash and the sbx MCP server, such as another MCP server that runs commands.

Treat sandbox output, copied files, OCR text, and screenshots as untrusted data; the `sbx` skill says the same to agents.
