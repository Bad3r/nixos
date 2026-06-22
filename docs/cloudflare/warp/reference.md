# WARP Module Reference

## Module options (`programs.cloudflare-warp.extended`)

| Option          | Type            | Default                                              | Description                                                                      |
| --------------- | --------------- | ---------------------------------------------------- | -------------------------------------------------------------------------------- |
| `enable`        | bool            | `false`                                              | Run `warp-svc` and enroll into Zero Trust.                                       |
| `package`       | package         | `pkgs.cloudflare-warp.override { headless = true; }` | WARP package; headless ships `warp-cli`/`warp-svc`/`warp-dex`/`warp-diag`.       |
| `organization`  | nullable string | `null`                                               | Zero Trust team name; `null` runs `warp-svc` without managed enrollment.         |
| `serviceMode`   | enum            | `"warp"`                                             | `mdm.xml` `service_mode`: `warp`, `tunnelonly`, `1dot1`, `proxy`, `postureonly`. |
| `autoConnect`   | int 0-1440      | `0`                                                  | `mdm.xml` `auto_connect` minutes before reconnect after a manual disconnect.     |
| `switchLocked`  | bool            | `false`                                              | `mdm.xml` `switch_locked`; when true the user cannot disconnect.                 |
| `connectOnBoot` | bool            | `true`                                               | Best-effort oneshot `warp-cli connect` after the daemon starts.                  |
| `openFirewall`  | bool            | `true`                                               | Open the WARP UDP port.                                                          |
| `udpPort`       | port            | `2408`                                               | WARP UDP port to open.                                                           |

## mdm.xml parameters

Linux reads the managed deployment file at `/var/lib/cloudflare-warp/mdm.xml`.
The file is a bare `<dict>` plist fragment: no `<?xml ...?>` declaration, no
DOCTYPE, and no `<plist>` wrapper. The module emits these keys:

| Key                  | Type    | Values / format                                       | Source         |
| -------------------- | ------- | ----------------------------------------------------- | -------------- |
| `organization`       | string  | Zero Trust team name                                  | `organization` |
| `auth_client_id`     | string  | Service-token Client ID (`...access`)                 | sops secret    |
| `auth_client_secret` | string  | Service-token Client Secret                           | sops secret    |
| `service_mode`       | string  | `warp`, `tunnelonly`, `1dot1`, `proxy`, `postureonly` | `serviceMode`  |
| `auto_connect`       | integer | `0`-`1440` (minutes)                                  | `autoConnect`  |
| `switch_locked`      | boolean | `<true/>` / `<false/>`                                | `switchLocked` |

Other Cloudflare-documented keys not emitted by this module (add to `mdmContent`
in `modules/apps/cloudflare-warp.nix` if needed): `support_url`,
`warp_tunnel_protocol` (`masque` or `wireguard`), `enable_post_quantum`,
`gateway_unique_id`, `display_name`. `unique_client_id` is iOS/Android/ChromeOS
only and is not valid on Linux.

Rendered example (placeholders shown; real values are injected by sops):

```xml
<dict>
  <key>organization</key>
  <string>my-team</string>
  <key>auth_client_id</key>
  <string>REDACTED.access</string>
  <key>auth_client_secret</key>
  <string>REDACTED</string>
  <key>service_mode</key>
  <string>warp</string>
  <key>auto_connect</key>
  <integer>0</integer>
  <key>switch_locked</key>
  <false/>
</dict>
```

## sops layout

| Item                   | Value                                                                     |
| ---------------------- | ------------------------------------------------------------------------- |
| Encrypted file         | `secrets/cloudflare-warp.yaml`                                            |
| Keys                   | `auth_client_id`, `auth_client_secret`                                    |
| Secret names           | `cloudflare-warp/auth_client_id`, `cloudflare-warp/auth_client_secret`    |
| Template               | `sops.templates."cloudflare-warp-mdm"` (mode 0600)                        |
| Rendered template path | `config.sops.templates."cloudflare-warp-mdm".path` (under `/run/secrets`) |
| Installed runtime file | `/var/lib/cloudflare-warp/mdm.xml` (0600 root, via ExecStartPre)          |
| `.sops.yaml` rule      | Covered by the existing catch-all (no policy change needed)               |

## Keeping the team name private

`organization` is not a credential, but it identifies the Zero Trust tenant, and
this repository is public. To keep it out of git, add it to the sops secret and
render it through a placeholder instead of the plaintext option:

1. Add `organization: <team>` to `secrets/cloudflare-warp.yaml`.
2. Declare `sops.secrets."cloudflare-warp/organization"`.
3. In `mdmContent`, replace `<string>${cfg.organization}</string>` with
   `<string>${config.sops.placeholder."cloudflare-warp/organization"}</string>`
   and drop the `organization` per-host option (or keep it only as a non-secret
   fallback).
