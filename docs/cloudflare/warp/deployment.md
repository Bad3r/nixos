# WARP deployment runbook

Procedures for enrolling a fleet host with the module in `modules/apps/cloudflare-warp.nix`.
API calls below use `curl` with `ACCOUNT` set to the account id and `CF_API_TOKEN` to an API token holding the Zero Trust write scopes; the dashboard shows the same objects.

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

3. Create the device profile `nixos-<host>`, matched on the token, with the host's mode (`warp` or `warp_tunnel_only`), MASQUE, `auto_connect` at zero, and the split-tunnel exclude list.

   ```sh
   curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/devices/policy" \
     -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
     --data '{"name": "nixos-<host>", "match": "identity.service_token_uuid == \"<token id>\"", "precedence": <unique integer>, "enabled": true, "service_mode_v2": {"mode": "<mode>"}, "tunnel_protocol": "masque", "auto_connect": 0, "switch_locked": false, "allow_mode_switch": true, "allowed_to_leave": false, "captive_portal": 180, "exclude": [{"address": "10.0.0.0/8"}, {"address": "100.64.0.0/11", "description": "CGNAT below the Cloudflare Mesh range"}, {"address": "100.112.0.0/12", "description": "CGNAT above the Cloudflare Mesh range"}, {"address": "169.254.0.0/16"}, {"address": "172.16.0.0/12"}, {"address": "192.0.0.0/24"}, {"address": "192.168.0.0/16"}, {"address": "224.0.0.0/24"}, {"address": "240.0.0.0/4"}, {"address": "255.255.255.255/32"}, {"address": "fe80::/10"}, {"address": "fd00::/8"}, {"address": "ff01::/16"}, {"address": "ff02::/16"}, {"address": "ff03::/16"}, {"address": "ff04::/16"}, {"address": "ff05::/16"}, {"address": "239.255.255.250/32", "description": "SSDP"}, {"address": "fc00::/7"}, {"address": "17.249.0.0/16", "description": "Apple services"}, {"address": "17.252.0.0/16", "description": "Apple services"}, {"address": "17.57.144.0/22", "description": "Apple services"}, {"address": "17.188.128.0/18", "description": "Apple services"}, {"address": "17.188.20.0/23", "description": "Apple services"}]}'
   ```

4. Set the default profile's exclude list to the same 24 entries: everything Cloudflare serves by default, with the stock `100.64.0.0/10` split into `100.64.0.0/11` and `100.112.0.0/12`; `exclude.json` holds that array.

   ```sh
   curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/devices/policy/exclude" \
     -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
     --data @exclude.json
   ```

5. In the dashboard, check that Mesh connectivity is on under Team & Resources, Devices, Management, and that the ICMP proxy is on next to TCP and UDP under Traffic policies, Traffic settings.

Verification: `GET /accounts/$ACCOUNT/devices/policies` lists the profile with the host's mode and a 24-entry exclude list, and the app's policies include the token id.

## Put the token into sops

Precondition: the shared host age key is in `.sops.yaml`; its catch-all `secrets/.*` rule covers the file.

1. In the secrets repository, copy `cloudflare-warp.yaml.example` to `cloudflare-warp.yaml` for a first host, or open the existing file with `sops secrets/cloudflare-warp.yaml`.

2. Set `organization` to the team name and add a `<host>` section with `auth_client_id` and `auth_client_secret`.

3. Encrypt from the repository root, then commit and push the secrets repository and bump the gitlink.

   ```sh
   sops -e -i secrets/cloudflare-warp.yaml
   git -C secrets add cloudflare-warp.yaml
   git -C secrets commit -m "feat(cloudflare-warp): add the <host> service token"
   git -C secrets push origin main
   git add secrets
   ```

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

## Record the Mesh address

Precondition: the host is enrolled and Connected.

1. Read the address: `ip -4 addr show CloudflareWARP | awk '/inet / { sub("/.*", "", $2); print $2 }'`.
2. Add `meshIp = "<address>";` to `flake.lib.nixos.hosts.<host>` in `modules/<host>/policy.nix` and commit; evaluation rejects an address outside `100.96.0.0/12`.
3. Switch every fleet host, since `/etc/ssh/ssh_known_hosts` and, on hosts that run WARP, `~/.ssh/hosts/<host>.warp` render at build time.

Verification: from another fleet host, `ssh <host>.warp true` succeeds with no host-key prompt.

## Change a profile's exclude list

Precondition: `exclude.json` holds the full 24-entry array from the profile step above, since the call replaces the whole list.

1. Set the list on a custom profile, with the id from `GET /accounts/$ACCOUNT/devices/policies`; the default profile takes the same body at `/devices/policy/exclude`.

   ```sh
   curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/devices/policy/<profile id>/exclude" \
     -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
     --data @exclude.json
   ```

2. Wait for the client's profile refresh, or `sudo systemctl restart cloudflare-warp.service` on the host.

Verification: `warp-cli --accept-tos settings` lists every entry under `Exclude mode`.

## Rotate a token

Precondition: the host's client secret leaked, or the token must stop working.

1. Create a replacement token and profile as in the first procedure, and add the new token id to `hosts-service-auth`.
2. Update the host's section in `secrets/cloudflare-warp.yaml`, commit, push, bump the gitlink, and switch the host; the changed template restarts `warp-svc`.
3. Delete the old registration with `warp-cli --accept-tos registration delete`, then `sudo systemctl restart cloudflare-warp.service`, so the daemon registers under the new token.
4. Delete the old token through the API or the dashboard; the deleted registration released the device address, so record the new `meshIp` afterwards.

Verification: `warp-cli --accept-tos registration show` reports the new profile, and the old token is gone from the service token list.

Source: [Deploy the client on headless Linux](https://developers.cloudflare.com/cloudflare-one/tutorials/deploy-client-headless-linux/).
