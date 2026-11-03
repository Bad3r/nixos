# warp-devices

`warp-devices` lists the team's active WARP registrations with their status, Mesh and public addresses, OS, and last contact, and prints one device's report timeline.
It reads the Zero Trust device and DEX APIs with a read-only token; the app module is `modules/apps/warp-devices.nix` and the code is `packages/warp-devices/`.

## Credentials

The token is account-owned and holds two account permissions: Zero Trust Read for the device endpoints and DEX Read for the status reports.
DEX Read alone answers the status endpoints but returns `Authentication error` on every device endpoint.
It lives at `zero_trust_read_api_token` in `secrets/cloudflare-warp.yaml`, apart from the Zero Trust Write token the enrolled hosts use.

When the app row is on, Home Manager sops renders two files readable only by the owner:

- `$XDG_RUNTIME_DIR/warp-devices/account-id` from `account_id`
- `$XDG_RUNTIME_DIR/warp-devices/api-token` from `zero_trust_read_api_token`

Each is a symlink into the sops-nix generation under the same per-user tmpfs, so the plaintext is never written to a disk filesystem.
Like any tmpfs page, it can still move to swap.
With `XDG_RUNTIME_DIR` unset or empty, the CLI fails unless both flags below name the files.

The key must exist in the secrets file before the switch, since a missing key fails the build before anything activates.
`--account-id-file` and `--token-file` point the CLI at other files, for example a process substitution:

```sh
warp-devices --account-id-file <(sops -d --extract '["account_id"]' secrets/cloudflare-warp.yaml) \
  --token-file <(sops -d --extract '["zero_trust_read_api_token"]' secrets/cloudflare-warp.yaml)
```

## List devices

```sh
warp-devices
warp-devices --ipv6 --user
warp-devices --json | jq '.devices[] | select(.status == "connected") | .name'
```

`list` is the default command.
The table shows `NAME`, `STATUS`, `MESH_IPV4`, `PUBLIC_IP`, `OS`, and `LAST_SEEN`; `--ipv6` adds the Mesh IPv6 column and `--user` the enrolled user.
Devices enrolled with a service token show `non_identity@<team>.cloudflareaccess.com` as their user.
Connected devices come first, then the rest by most recent contact.
`LAST_SEEN` reads as an age under a day and as a local date and time past it.

`STATUS` is the newest DEX fleet-status report within the longest window the endpoint accepts:

| Value                                          | Meaning                                                                         |
| ---------------------------------------------- | ------------------------------------------------------------------------------- |
| `connected`, `connecting`, `disconnected`, ... | the client's last report, as sent                                               |
| `offline`                                      | no report in that window                                                        |
| `unknown`                                      | the DEX endpoint failed or returned malformed data, or the report had no status |

An awake client reports every two minutes and a sleeping one about every twenty.
A device that loses power or network keeps its last reported status, often `connecting`, until its report ages out of the window.

## Show a device's history

```sh
warp-devices history laptop
warp-devices history laptop --hours 72 --all
```

The device is a name, matched without case, or a device ID; a name two devices share fails and lists both IDs.
`--hours` takes up to the seven days DEX keeps raw reports; `warp-devices history --help` gives the range and default.
The table prints the first and last report and every report whose status, colo, ISP address, LAN address, or gateway changed, or that follows a long gap; `--all` prints every report.
`GAP` is the time since the report before it, so a long gap after `connecting` reads as the client going quiet, usually asleep or offline.

## Output and exit codes

`--json` prints every field with the API's raw timestamps, plus a `warnings` list for `list`.
Color is on for a terminal unless `NO_COLOR` holds a non-empty value; `--color` and `--no-color` override it.

Tables and stderr print control and format characters in API text escaped, so a device name cannot drive the terminal or reorder and hide text.
`--json` keeps them as JSON escapes.

| Code | Meaning                            |
| ---- | ---------------------------------- |
| 0    | success, warnings included         |
| 1    | API, credential, or data failure   |
| 2    | usage error                        |
| 3    | no device or more than one matched |
| 130  | interrupted                        |
| 141  | output pipe closed                 |

## Failures

The device endpoints stall now and then or cut a response short, so connecting and each read time out.
A request retries with backoff on a timeout, a cut-off or malformed body, HTTP 408, 429 (honoring `Retry-After`), or any 5xx.
Network errors retry the same way, such as a DNS failure, a refused or unreachable connection, or a TLS error.
A failed TLS certificate check or any other status is final, so a 403 fails at once and names the two permissions the token needs.

A pagination cursor that stops advancing or loops fails the endpoint rather than returning a partial list.
A failed registrations endpoint fails the command, since it carries the device list and the Mesh addresses.
A failed physical-devices or DEX endpoint prints a warning naming it, empties its columns or sets `STATUS` to `unknown`, and still exits 0.
Malformed DEX data, such as a report without a readable timestamp, degrades the same way; malformed registrations data fails the command.

Source: [Zero Trust devices API](https://developers.cloudflare.com/api/resources/zero_trust/subresources/devices/).
