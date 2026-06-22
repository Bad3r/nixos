# WARP Zero Trust Deployment

Operator runbook to enroll a host into Cloudflare Zero Trust with this
configuration. Dashboard steps target an Enterprise Zero Trust account.

## 1. Dashboard prerequisites (one time)

1. **Team name.** Note the `<team>` in `<team>.cloudflareaccess.com`. This becomes
   the `organization` option.
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
`.sops.yaml` catch-all rule.

```bash
sops secrets/cloudflare-warp.yaml
```

Enter the service-token values:

```yaml
auth_client_id: <client-id>.access
auth_client_secret: <client-secret>
```

Verify and stage inside the submodule:

```bash
sops -d secrets/cloudflare-warp.yaml          # shows both keys
git -C secrets add cloudflare-warp.yaml
```

## 3. Enable the host

Each host opts in through a small file that sets the `organization` (team name)
and Full mode:

- `modules/tpnix/cloudflare-warp.nix`
- `modules/system76/cloudflare-warp.nix`

```nix
_: {
  configurations.nixos.<host>.module = {
    programs.cloudflare-warp.extended = {
      enable = true;
      organization = "<your-team-name>";
      serviceMode = "warp";
      autoConnect = 0;
      switchLocked = false;
      connectOnBoot = true;
    };
  };
}
```

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
