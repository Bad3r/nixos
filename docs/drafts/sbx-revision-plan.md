# sbx revision plan

`sbx` moves from a disposable detonation box to the agents' own machines with selectable isolation.
Five stages, each shippable alone: fix what hurt, bases, networks, persistence, agent workspaces.
The usage evidence behind each item sits in `/data/agents/sbx-usage-review/`.

## Properties that hold through every stage

- A guest stays untrusted: host files reach it only through the copy roots, a share, a volume, or a closure copy.
- A sandbox network reaches the internet only, unless its declaration opens the LAN or Mesh; none reaches the host except through a grant.
- No housekeeping job takes a mount or a network away from a running sandbox.
- The CLI, the MCP server, and `sbx gc` read one settings file at call time.
- Nothing an agent does with `sbx` needs sudo or a polkit prompt.
- `gc` never removes a volume, a saved base in use, or a persistent sandbox.
- Each stage states what happens to sandboxes that run across the switch that installs it.

## Stage 1: fix what hurt

| Change                         | Where                                                                                     |
| ------------------------------ | ----------------------------------------------------------------------------------------- |
| Settings read at call time     | `packages/sbx/default.nix`, `packages/sbx/sbx/config.py`, `packages/sbx/sbx/mcp.py`       |
| `sbx limits`                   | `packages/sbx/sbx/ops.py`, `packages/sbx/sbx/storage.py`, `packages/sbx/sbx/admission.py` |
| `gc` leaves shares attached    | `packages/sbx/sbx/ops.py`, `packages/sbx/sbx/shares.py`                                   |
| `sbx ttl <name> <duration>`    | `packages/sbx/sbx/lifecycle.py`, `packages/sbx/sbx/context.py`                            |
| `create --disk`                | `packages/sbx/sbx/lifecycle.py`, `modules/apps/sbx/nixos.nix`                             |
| `nixos` base runs foreign code | `modules/apps/sbx/_base-nixos.nix`                                                        |
| Stale base reported            | `packages/sbx/sbx/bases.py`                                                               |
| Three features removed         | see [Removals](#removals)                                                                 |

- The launchers stop baking a settings store path; they read a fixed path under `/etc`, and `sbx-mcp` loads it for every call.
  The file carries a schema version, and a process older than the file refuses with a message that names the restart.
- A drop-in file in the owner's config directory overrides single limits without a switch.
  All three front ends read it with the settings, and `sbx limits` and the journal name every limit it changes.
- `sbx limits` prints each ceiling, the usage against it, per-sandbox disk split into overlay, share, and `xfer`, the free space against the floor, and the settings path.
  Every refusal quotes the same numbers.
- `gc` stops calling `Shares.reclaim`.
  Past the disk cap or below the free-space floor, `create`, `cp`, and `share attach` refuse; running sandboxes keep their mounts.
- `sbx ttl` moves the expiry to at most the longest TTL from now, and works on an expired sandbox that `gc` has not removed yet, so its files can still be copied out.
- The `nixos` base gains `nix-ld` with a common library set, `/opt`, `/usr/local/bin`, `/bin/bash`, `gcc`, `make`, `jq`, `ripgrep`, `wget`, `p7zip`, and the `nix-command` and `flakes` features.
- `base list` marks a base whose out-link differs from the image the installed configuration expects.
- The CLI sets `XDG_RUNTIME_DIR` when it is unset, as `sbx-mcp` does.

Checks: the `sbx` unit tests, the `sbx-vsock` and `sbx-gui` VM checks, and a new subtest in which one sandbox fills its share past the cap while a second keeps its mount.
On `songbird`: a ceiling change reaches a running MCP server without a restart.

### Removals

| Feature             | Goes with it                                                                                                                    |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Windows bases       | `windows.py`, `export.py`, the `sbx-base@` unit, `windowsBases`, the `sbx-windows-base` check, `docs/apps/sbx/windows.md`       |
| vsock grants        | `vsock.py`, the `sbx-vsock` socket and service, `packages/workloads/workloads/vsock.py`, the `sbx-vsock-grants` check, its page |
| Capacity wait queue | `waitqueue.py`, `--wait`, the queue branch of `admission.py`, the `queued` state of `list`                                      |

The per-sandbox vsock namespace in `emulator.py` stays: it is isolation, not grants.
The skill, the MCP schema snapshot, and the `workloads` CLI branches for each feature go in the same change.

## Stage 2: bases

- A base is an image source, a provisioning recipe, and capabilities, all declared in Nix.
  The declaration replaces `FLAVOURS` and `GUI_BASES` in `packages/sbx/sbx/model.py` and the single prepare script in `packages/sbx/sbx/cloud.py`.
- New declared bases: the latest Ubuntu LTS cloud image, `ubuntu-gui` with IceWM, xterm, and xdotool as `nixos-gui` has, and `ubuntu-desktop` with the stock desktop packages as a reference install.
- An agent session may build any declared base; the owner-only refusal in `packages/sbx/sbx/prepare.py` and the harness ask rules go.
- `sbx base save <sandbox> <name>` turns a provisioned sandbox into a base.
  A saved base records its creator and parent, cannot take a declared name, counts against the disk cap, and expires after 90 days without use.
- Both GUI bases gain the X inspection tools, `xvfb-run`, an AT-SPI session bus with toolkit accessibility on, Mesa software rendering, and a fuller font set.
- `key`, `type`, `mouse`, `window`, and `screenshot` take `--display`, so an app on an Xvfb display in any base is driven and captured as one on `:0` is.
- `sbx view <name>` opens a viewer on the sandbox's SPICE socket on the host desktop.
- `sbx cp --closure <store path> <name>:` copies a store path with its closure and registers it in the guest.
- Screenshots of the owner's own desktop configuration stay on the host, which has its store, fonts, theme, and GPU.
  A maintained tool wraps the `unshare` and Xvfb recipe with a private `/tmp` and home, and the skill sends that case there.

Checks: one VM check per base kind, with the GUI check also run against `ubuntu-gui`.

To verify first:

- Whether the Ubuntu LTS cloud image ships `systemd-ssh-generator`.
- Whether `ubuntu-desktop` still offers an X11 session; without one the xdotool verbs do not apply there and the base serves screenshots only.

## Stage 3: networks

- `create --net <name>` selects a declared workload network; `egress` stays as the name of the WARP one.
- `modules/workloads/networks.nix` gains the egress kind `direct`, which routes a bridge's traffic through the main table to the uplink and drops the LAN ranges, the host, and Mesh in the forward chain.
- A declared network opens the LAN with `lanAccess` and Mesh with a new `meshAccess`.
  Guests reach those devices from behind the host's address, and an agent joins such a network as it joins any other.
- `create --net vpn --country <cc> [--port-forward]` leases one of six slots.
  A slot is a declared bridge, a network namespace whose only route is a WireGuard tunnel, and one Proton key from sops.
- `workload-grantd` gains the tunnel request: it validates the country against a server list kept in the repository, brings the tunnel up with a firewall mark that sends its packets past WARP, and tears it down with the sandbox.
- With `--port-forward` the helper renews the NAT-PMP mapping, forwards the port to the guest, and `sbx info` reports it.
- An exhausted pool refuses and names the holders.

Checks: a VM check with a local WireGuard peer in which the guest reaches the peer only through the tunnel and loses all traffic when the tunnel drops; a subtest per network kind that the LAN and Mesh answer only where the declaration opens them and the host never does.
On `songbird`: the exit address of each network kind.

To verify first:

- One Proton key working on every server; the reports are from users, not from Proton.
- One forwarded port per tunnel, and how Proton counts a manual tunnel against the account's session limit.
- The priority of WARP's own routing rules against the firewall-mark rule.

## Stage 4: persistence

- `sbx volume create|list|rm` manages named disk images of a fixed size outside every run directory.
  `create --volume <name>` attaches one; the fixed size is the quota.
- `create --persistent` makes a sandbox with no expiry that `gc` skips and that cold-starts from its disk after a host reboot.
- Sandboxes, saved bases, and volumes carry an owner label, by default the session; `--mine` matches the label, and removing something under another label needs `--force`.
- `sbx limits` lists persistent sandboxes and volumes with their last use.

Checks: a volume outlives `destroy`, expiry, and `gc`; a persistent sandbox outlives `gc` and a reboot of the test host.

## Stage 5: agent workspaces

- A declared `agent` base carries Claude Code and Codex from the flake's own packages.
- `create` attaches one project directory as a live share; beyond it, only the credential files below leave the owner's home.
- Each harness in the guest uses the owner's existing sign-in, so the provider sees one login per account.
  Only the credential files enter the guest, not the harness's history, memory, or settings.
- Search and fetch stay on the host and the guest calls them through a grant, so browser cookies never enter a guest.
- Plugins, skills, fonts, and themes arrive through declared read-only shares (`workloads.grants.sandboxShares`).
- `list` labels a sandbox that holds a credential, and the skill keeps unknown code out of it.

Checks: a VM check in which a harness in the `agent` base completes a turn against a stub endpoint with a test credential and sees no host path but the project directory.

To verify first:

- How each harness refreshes its token when the host and a guest hold the same session, and whether a refresh on one side ends the other's.
- Whether the credential files can be shared live, so a refresh on either side reaches both.
