# MCP Tools

Model Context Protocol (MCP) tools that may be available when configured. Use `/mcp` to check current configuration status.

| Tool                  | Primary Use                                             | Access Notes                                                             | Example Invocation                                                          |
| --------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| `context7`            | Look up library IDs and documentation for coding tasks. | Requires network; resolves ID before fetching docs.                      | `context7 resolve-library-id --name <library>`                              |
| `openaiDeveloperDocs` | Search OpenAI developer docs and API references.        | Configured for Codex only via remote MCP endpoint.                       | `codex mcp add openaiDeveloperDocs --url https://developers.openai.com/mcp` |
| `cfdocs`              | Search Cloudflare documentation.                        | Use for Workers, R2, and other CF services.                              | `cfdocs search --query "Workers KV"`                                        |
| `cfbrowser`           | Render and capture live webpages.                       | Useful for verifying UI changes.                                         | `cfbrowser get-url-html --url <page>`                                       |
| `chrome-devtools`     | Control and inspect a live Chrome browser session.      | Google-maintained server; isolated profile + no usage stats recommended. | `npx -y chrome-devtools-mcp@latest --isolated --no-usage-statistics`        |
| `deepwiki`            | Browse repository knowledge bases.                      | Supply `owner/repo` to fetch docs.                                       | `deepwiki read_wiki_structure --repo owner/repo`                            |
| `playwright`          | Automate browser interactions for UI and E2E checks.    | Runs locally via NPX package with isolated profile.                      | `npx -y @playwright/mcp@latest --isolated`                                  |
| `time`                | Convert or fetch timestamps.                            | No prerequisites.                                                        | `time convert --from UTC --to America/Los_Angeles`                          |
| `sequential-thinking` | Record structured reasoning steps.                      | Use for complex tasks; keeps plan visible.                               | `sequentialthinking start`                                                  |
