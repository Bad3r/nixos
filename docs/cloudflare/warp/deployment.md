# WARP deployment runbook

Procedures for enrolling a fleet host with the module in `modules/apps/cloudflare-warp.nix`.
API calls below use `curl` with `ACCOUNT` and `CF_API_TOKEN` taken from `secrets/cloudflare-warp.yaml` through `sops -d --extract` on `account_id` and `zero_trust_api_token`, an account-owned token holding Zero Trust Write that verifies at `/accounts/$ACCOUNT/tokens/verify` rather than `/user/tokens/verify`; the dashboard shows the same objects.

## Create the Cloudflare objects for a host

Precondition: the Zero Trust team exists and the account holds the `Warp Login App` Access application.

1. Create a service token named `nixos-<host>` and keep the client id and client secret from the response; the secret is shown once.

   ```sh
   curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/access/service_tokens" \
     -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
     --data '{"name": "nixos-<host>", "duration": "forever"}'
   ```

2. Add the token id to the Service Auth policy `hosts-service-auth` on the `Warp Login App`, or create that policy with decision `non_identity` when it does not exist.

   ```sh
   curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/access/apps/<warp app id>/policies" \
     -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
     --data '{"name": "hosts-service-auth", "decision": "non_identity", "precedence": 2, "include": [{"service_token": {"token_id": "<token id>"}}]}'
   ```

3. Create the device profile `nixos-<host>`, matched on the token, with the host's mode (`warp` or
   `warp_tunnel_only`), WireGuard, and `auto_connect` at zero.
   Its exclude list is set once the token is in sops.

   ```sh
   curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/devices/policy" \
     -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
     --data '{"name": "nixos-<host>", "match": "identity.service_token_uuid == \"<token id>\"", "precedence": <unique integer>, "enabled": true, "service_mode_v2": {"mode": "<mode>"}, "tunnel_protocol": "wireguard", "auto_connect": 0, "switch_locked": false, "allow_mode_switch": true, "allowed_to_leave": false, "captive_portal": 180}'
   ```

4. In the dashboard, check that Mesh connectivity is on under Team & Resources, Devices, Management, and that the ICMP proxy is on next to TCP and UDP under Traffic policies, Traffic settings.

Verification: `GET /accounts/$ACCOUNT/devices/policies` lists the profile with the host's mode, and the app's policies include the token id.

## Put the token into sops

Precondition: the shared host age key is in `.sops.yaml`; its catch-all `secrets/.*` rule covers the file.

1. In the secrets repository, copy `cloudflare-warp.yaml.example` to `cloudflare-warp.yaml` for a first host, or open the existing file with `sops secrets/cloudflare-warp.yaml`.

2. Set `organization` to the team name, set `mesh.cidr` to the account's Mesh allocation, and add a
   `<host>` section with `auth_client_id` and `auth_client_secret`.
   Existing enrolled hosts keep one address each under `mesh.hosts.<host>`.

3. Encrypt from the repository root, then commit and push the secrets repository and bump the gitlink.

   ```sh
   sops -e -i secrets/cloudflare-warp.yaml
   git -C secrets add cloudflare-warp.yaml
   git -C secrets commit -m "feat(cloudflare-warp): add the <host> service token"
   git -C secrets push origin main
   git add secrets
   ```

4. Set the new profile's exclude list per [Change an exclude list](#change-an-exclude-list).

Verification: `nix flake check path:. --accept-flake-config --no-build --offline` passes, including the cleartext guard.

## Enroll the host

Precondition: `modules/<host>/policy.nix` sets `sopsRuntimeReady = true`, `modules/<host>/apps-enable.nix` turns `cloudflare-warp` on, and `modules/<host>/cloudflare-warp.nix` sets `serviceMode`.

1. Turn ProtonVPN autoconnect off and bring the connection down if it is up, since two default-route tunnels cannot share a host:
   `nmcli con mod "<ProtonVPN connection>" connection.autoconnect no` and `nmcli con down "<ProtonVPN connection>"`.

2. Build and switch: `./build.sh`.

3. Check the daemon, the registration, and the mode.

   ```sh
   systemctl status cloudflare-warp.service
   warp-cli --accept-tos registration show
   warp-cli --accept-tos status
   warp-cli --accept-tos settings
   ```

4. Check the tunnel: `ip addr show CloudflareWARP` shows the Mesh address, and `curl -s https://www.cloudflare.com/cdn-cgi/trace | grep warp=` prints `warp=on`.

5. Reboot, then repeat step 3; the status reaches Connected with no manual command.

Verification: the dashboard lists the device under Team & Resources, Devices as `non_identity@<team>.cloudflareaccess.com` with the profile `nixos-<host>`.

## Store a Mesh address

Precondition: the host is enrolled and Connected, and its host key is pinned per [Pin the SSH host key](../../guides/host-onboarding-secrets.md#pin-the-ssh-host-key).

1. Read the address: `ip -4 addr show CloudflareWARP | awk '/inet / { sub("/.*", "", $2); print $2 }'`.
2. Store it at `mesh.hosts.<host>` in `secrets/cloudflare-warp.yaml` with `sops`, then commit and
   push the secrets repository and bump its gitlink.
3. Set `cloudflareWarpMeshAddressReady = true` in `modules/<host>/policy.nix` after the encrypted
   value exists.
4. Switch every WARP fleet host, since sops-nix renders `/etc/hosts` from the encrypted addresses
   and Home Manager renders `~/.ssh/hosts/<host>.internal` from the readiness flag.

Verification: from another fleet host, `getent ahostsv4 <host>.internal` prints the Mesh address,
`ping -c 1 <host>.internal` answers, and `ssh <host>.internal true` asks 1Password to use the dedicated SSH
authentication key and succeeds with no host-key or password prompt. Both the source and
destination must run the new configuration: the source selects the 1Password agent key, and the
destination authorizes it.

1Password is configured to scope approval to each application and terminal session. A second SSH
command from the same approved terminal tab may not prompt again until 1Password locks or the
session expires. When the installed 1Password version offers `For each new request`, select it in
Settings, Developer, SSH Agent, Advanced to require approval for every SSH signature request.

## Change an exclude list

Precondition: the base list in `modules/apps/cloudflare-warp/excludes-package.nix` and each `<host>.exclude` list in `secrets/cloudflare-warp.yaml` hold the wanted entries.

`cloudflare-warp-excludes` gives the default profile the base list and each `nixos-<host>` profile the base list plus that host's entries.
An entry added only in the dashboard shows as `-` in the comparison and is dropped on `--apply`.
A `warp_tunnel_only` profile ignores `host` entries, since domain excludes need the client's DNS proxy, so such a host lists the destination's address range.
The Proton VPN WireGuard endpoint in [qbittorrent.nix](../../../modules/songbird/qbittorrent.nix) stays inside the WARP tunnel, because the ISP drops a WireGuard flow it can see and an excluded endpoint gets no handshake.

1. From the repository root, compare each profile with its declared list:

   ```sh
   nix run path:.#cloudflare-warp-excludes
   ```

2. Replace every list that differs: `nix run path:.#cloudflare-warp-excludes -- --apply`.

3. Run `sudo systemctl restart cloudflare-warp.service` on each changed host: warp-svc 2026.7.1343.0 can keep the previous list past Cloudflare's ten-minute propagation window.

Verification: a second comparison reports every profile up to date, and `warp-cli --accept-tos settings` on the host lists every entry under `Exclude mode`.

## Rotate a token

Precondition: the host's client secret leaked, or the token must stop working.

1. Create a replacement token and profile as in the first procedure, and add the new token id to `hosts-service-auth`.
2. Update the host's section in `secrets/cloudflare-warp.yaml`, commit, push, bump the gitlink, and switch the host; the changed template restarts `warp-svc`.
3. Delete the old registration with `warp-cli --accept-tos registration delete`, then `sudo systemctl restart cloudflare-warp.service`, so the daemon registers under the new token.
4. Delete the old token through the API or the dashboard; the deleted registration releases the
   device address, so replace `mesh.hosts.<host>` per [Store a Mesh address](#store-a-mesh-address)
   and switch every WARP fleet host.

Verification: `warp-cli --accept-tos registration show` reports the new profile, and the old token is gone from the service token list.

Source: [Deploy the client on headless Linux](https://developers.cloudflare.com/cloudflare-one/tutorials/deploy-client-headless-linux/).
