# sbx for agents

With the `sbx` row on, Claude Code and Codex get the `sbx` skill from `modules/agents/skills/sbx.nix`, a system-prompt line, and an allow rule for `sbx`.
The Codex allow rule in `modules/agents/codex/_exec-policy.nix` also runs `sbx` outside bwrap, since the CLI writes its state directory and starts user units.

## MCP server

Both clients start `sbx-mcp`, the `sbx` entry in `modules/agents/mcp/servers.nix`, whose tools, one per agent-facing verb, take the verb's arguments by name and return its `--json` document.

- The screenshot tool also returns a PNG image content block for direct visual inspection, alongside the saved path and MIME type.
- Its optional `ocr` argument adds Tesseract output under `text`; image inspection needs no OCR.
- Codex names its session in every tool call, and `CODEX_SESSION_ID` in every shell, so `--mine` matches sandboxes from the CLI and the MCP tools alike.
- Claude Code passes its session only when it starts the server, so after `/clear` the tools keep the old session until `/mcp` reconnects `sbx`.
- Under MCP, the checkout copy root and relative host paths follow the directory the client started in.
