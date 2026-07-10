# WARP Zero Trust Deployment

Operator runbook to enroll a host into Cloudflare Zero Trust with this
configuration. Dashboard steps target an Enterprise Zero Trust account.

## 1. Dashboard prerequisites (one time)

1. **Team name.** Note the `<team>` in `<team>.cloudflareaccess.com`. This becomes
   the `organization` key in the sops secret (step 2). Use the bare team name,
   not the full hostname.
2. **Service token.** Settings/Access > Service Auth > Create Service Token.
   Capture the **Client ID** (ends in `.access`) and the **Client Secret** (shown
   once). These become `auth_client_id` / `auth_client_secret`.
3. **Device-enrollment permission.** Settings > WARP Client > Device enrollment
   permissions > Manage. Add a rule whose action is **Service Auth**, including
   the service token from step 2. Required for token enrollment; without it the
   daemon enrolls then fails policy.
4. **Device profile.** Settings > WARP Client > Device profiles > Default >
   Service mode = **Gateway with WARP** so dashboard policy matches the local
   `service_mode = warp`.
5. **Split Tunnels (Exclude IPs).** Keep the default RFC1918 ranges excluded and
   ADD Tailscale's `100.64.0.0/10` so the tailnet keeps working under full
   tunnel. Confirm `10.0.0.0/8` (the LAN range used by the tpnix SSH firewall
   rule) stays excluded.
6. **Local Domain Fallback.** Add internal/dev domains (for example `local`,
   `internal`, corporate AD) so they resolve outside Cloudflare DNS.

## 2. Create the encrypted secret

The secret lives in the `secrets/` submodule and is covered by the existing
`.sops.yaml` catch-all rule. Copy `secrets/cloudflare-warp.yaml.example` for the
expected key layout.

```bash
sops secrets/cloudflare-warp.yaml
```

Enter the team name and the service-token values:

```yaml
organization: <team>
auth_client_id: <client-id>.access
auth_client_secret: <client-secret>
```

Verify and stage inside the submodule:

```bash
sops -d secrets/cloudflare-warp.yaml          # shows all three keys
git -C secrets add cloudflare-warp.yaml
```

## 3. Enable the host

Each host opts in through a small file that enables the wrapper in Full mode:

- `modules/system76/cloudflare-warp.nix` sets `enable = true` directly; system76
  has runtime SOPS decryption.
- `modules/system76/cloudflare-warp.nix` sets `enable = true` directly; system76
  has runtime SOPS decryption.
- `modules/tpnix/cloudflare-warp.nix` sets `enable = sopsRuntimeReady`, gating on
  `flake.lib.nixos.hosts.tpnix.sopsRuntimeReady` (`modules/tpnix/policy.nix`) like
  the other tpnix sops consumers (`duplicati.nix`, `printing.nix`, `fonts.nix`).
  The flag is currently `true` (repo-managed sops landed for tpnix in PR #305), so
  the wrapper behaves like system76's: un-enrolled degraded mode until
  `secrets/cloudflare-warp.yaml` is committed, then non-interactive enrollment.
  The gate remains a kill switch: if tpnix ever loses its runtime decryption key,
  flipping the flag back to `false` drops the `cloudflare-warp/*` secret
  declarations that would otherwise fail activation on an un-decryptable payload.

A SOPS-ready host enables directly:

```nix
_: {
  configurations.nixos.<host>.module = {
    programs.cloudflare-warp.extended = {
      enable = true;
      serviceMode = "warp";
      autoConnect = 0;
      switchLocked = false;
      connectOnBoot = true;
    };
  };
}
```

A host still gated by `sopsRuntimeReady` (tpnix) enables through the flag; flip it in
`modules/tpnix/policy.nix` once the decryption key is in place:

```nix
{ config, ... }:
let
  inherit (config.flake.lib.nixos.hosts.tpnix) sopsRuntimeReady;
in
{
  configurations.nixos.tpnix.module = {
    programs.cloudflare-warp.extended = {
      enable = sopsRuntimeReady;
      serviceMode = "warp";
      autoConnect = 0;
      switchLocked = false;
      connectOnBoot = true;
    };
  };
}
```

The team name is not set here; it comes from the `organization` key in the sops
secret. On a SOPS-ready host, until `secrets/cloudflare-warp.yaml` exists the host
runs `warp-svc` un-enrolled and emits a build warning. A host still gated by
`sopsRuntimeReady` stays off entirely until the flag is `true`.

## 4. Validate and deploy

```bash
nix fmt
nix flake check --accept-flake-config --no-build --offline
nix build .#nixosConfigurations.<host>.config.system.build.toplevel --no-link
sudo nixos-rebuild switch --flake .#<host>
```

After switch, follow [Operations](./operations.md) to confirm enrollment,
connection, and coexistence with Tailscale and DNS.

## 5. Commit

The encrypted secret is committed inside the submodule; the Nix changes in the
main repository. Keep them as separate commits, then update the submodule pointer
in the main repo.
