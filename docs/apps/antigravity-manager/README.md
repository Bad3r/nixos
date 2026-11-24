# Antigravity Manager

Antigravity Manager pools Google Antigravity accounts behind a local Anthropic, OpenAI, and Gemini compatible API proxy, and switches the account `agy` and the Hub sign in with.
The options live in [the NixOS module](../../../modules/apps/antigravity-manager/nixos.nix), and the service and client wiring in [the Home Manager module](../../../modules/apps/antigravity-manager/home.nix).
The package builds from source in [packages/antigravity-manager](../../../packages/antigravity-manager/default.nix).
Upstream documentation: <https://github.com/lbjlaq/Antigravity-Manager>

## Service and web UI

`antigravity-server` runs as the `antigravity-manager` user service, bound to loopback, and serves the proxy and the management web UI on one port.
The web UI answers at `http://antigravity-manager.internal`, a [loopback site](../../networking/loopback-sites.md).
It asks for the proxy API key, which the server generates on first start and keeps in `~/.antigravity_tools/gui_config.json`:

```bash
systemctl --user status antigravity-manager
antigravity-manager-key
```

Add accounts under Accounts, Add Account, OAuth.
Google redirects to the proxy's `localhost` callback, so finish the flow in a browser on the same machine.

## Claude Code

`claude-antigravity` runs the Claude Code launcher with `ANTHROPIC_BASE_URL` set to the proxy and the API key as `ANTHROPIC_AUTH_TOKEN`.
Plain `claude` keeps using the claude.ai login, which the env token outranks only inside `claude-antigravity`.
The proxy maps Claude model names onto the models the account pool serves.

## Codex

`codex --profile antigravity` layers `~/.config/codex/antigravity.config.toml` over the merged config.
The profile points Codex at the proxy's Responses endpoint, reads the key through `antigravity-manager-key`, and requests the model in `codexModel`.
Pick another pool model for one session with `-m`:

```bash
codex --profile antigravity -m gemini-4-carbon-high
```

Codex has no metadata for pool models and warns that it falls back to defaults.

## Antigravity account switching

`antigravity-server switch` run in the login session writes the account's token to the Secret Service `login` collection and the token files under `~/.gemini`, where `agy` reads it.
The headless service refuses `agy` switches for lack of keyring access, so the CLI performs them itself; `-c` then resumes the last `agy` session:

```bash
antigravity-server list
antigravity-server switch 2 -c
```

Switching the Hub's account needs the GUI's desktop integration; the headless service records other targets only in memory.

## Leave alone

- The web UI's one-click sync for Claude Code, Codex, and Gemini rewrites settings files that the agent modules own; the launcher and profile replace it.
- `antigravity-tools` without arguments opens the Tauri GUI, which starts a second proxy on the same port and data directory; stop the service before opening it.
- Moving the data directory from the web UI breaks `antigravity-manager-key`, which reads the default location.

## Privacy

`~/.antigravity_tools` holds every pooled account's OAuth refresh token, request logs, and a store of model reasoning.
The prompt sanitizer rewrites client identity text in requests by default; its rules sit in the web UI's proxy settings.
