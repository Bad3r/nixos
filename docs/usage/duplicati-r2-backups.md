# Duplicati → Cloudflare R2 Backups

This repository ships a NixOS module that wires `duplicati-cli` up to
Cloudflare R2 using its S3-compatible API. It provisions:

- a SOPS-managed dotenv at `/etc/duplicati/r2.env` with the R2 credentials and
  encryption passphrase
- declarative oneshot/timer units (`duplicati-r2-backup-<name>.{service,timer}`)
  that run `duplicati-cli backup`
- optional verification timers (`duplicati-r2-verify-<name>.{service,timer}`)
  that sample archives with `duplicati-cli test`
- a runtime manifest rendered under `/run/duplicati-r2/config.json` that never
  touches the Nix store

## 1. Prepare secrets

Create `secrets/duplicati-r2.yaml` and encrypt it in place:

```bash
nix develop -c sops -e -i secrets/duplicati-r2.yaml
```

Populate the YAML with the credential selectors expected by
`services.duplicati-r2.credentials` (default mapping shown):

```yaml
duplicati-r2:
  AWS_ACCESS_KEY_ID: <ACCESS_KEY_ID>
  AWS_SECRET_ACCESS_KEY: <SECRET_ACCESS_KEY>
  R2_ACCOUNT_ID: <ACCOUNT_ID>
  R2_S3_ENDPOINT: <ACCOUNT_ID>.r2.cloudflarestorage.com
  R2_S3_ENDPOINT_URL: https://<ACCOUNT_ID>.r2.cloudflarestorage.com
  R2_API_TOKEN: <API_TOKEN>
  R2_BUCKET: duplicati-nixos-backups
  DUPLICATI_PASSPHRASE: change-me
```

If your bucket enforces a jurisdiction-specific endpoint (for example,
`https://<account>.eu.r2.cloudflarestorage.com`), add:

```
  R2_REGION: eu
```

Setting `R2_REGION` ensures the helper exports `AWS_REGION=eu`/`AWS_DEFAULT_REGION=eu`
and appends `s3-ext-region=eu` to the Duplicati destination, matching the Cloudflare
R2 S3 compatibility guidance.citeturn0cfdocs\_\_search_cloudflare_documentation0

> The passphrase is mandatory--Duplicati refuses to run encrypted backups without
> it. Rotate it with `sops -d` + `openssl rand -base64 32` when needed.
> If you use different key names, override
> `services.duplicati-r2.credentials.<name>.secret` to match the new selector.

## 2. Author the encrypted manifest

Describe the folders and schedules in `secrets/duplicati-config.json`. Keep the
file encrypted with SOPS; the module uses the template mechanism to render the
plaintext manifest at activation time. citeturn0search1

```bash
nix develop -c sops -e -i secrets/duplicati-config.json
```

Example manifest:

```json
{
  "environmentFile": "/etc/duplicati/r2.env",
  "bucket": "duplicati-nixos-backups",
  "hostname": "system76",
  "targets": {
    "bankdata-jim-woodring": {
      "path": "/bankData/Jim Woodring",
      "onCalendar": "Tue,Fri 03:00:00",
      "retention": "12M:1M"
    },
    "photos": {
      "path": "/srv/photos",
      "onCalendar": "daily",
      "extraArgs": ["--throttle-upload=5MB"]
    }
  },
  "verify": {
    "onCalendar": "weekly",
    "samples": 50
  }
}
```

Schema reference:

- `environmentFile` (optional) – path to the rendered dotenv with credentials.
- `bucket` (optional) – Cloudflare R2 bucket, defaults to `duplicati-nixos-backups`.
- `hostname` (optional) – override for the hostname segment inside the bucket.
- `targets` – object keyed by target slug. Each value supports:
  - `path` – absolute directory to back up (required).
  - `onCalendar` – systemd timer expression (required).
  - `retention` – Duplicati retention rule (`null` to disable).
  - `extraArgs` – list of extra CLI flags.
  - `stateDir` – override for the per-target SQLite directory.
  - `destSubpath` – override destination prefix inside the bucket.
- `verify` (optional) – `{ "onCalendar": "...", "samples": 200 }` to enable periodic verification.

## 3. Wire the module

Import the module together with `sops-nix`, point it at the encrypted manifest,
and enable the service:

```nix
{ inputs, ... }: {
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.self.nixosModules."duplicati-r2"
  ];

  sops.age.keyFile = "/var/lib/sops-nix/key.txt";

  services.duplicati-r2 = {
    enable = true;
    configFile = inputs.secrets + "/duplicati-config.json";
  };
}
```

During activation `sops-install-secrets` decrypts the manifest and rewrites
runtime unit files via the `duplicati-r2-generate-units.service`. The rendered
manifest lives at `/run/duplicati-r2/config.json` and every timer/service points
to it through `DUPLICATI_R2_CONFIG`.

> Prefer encrypted manifests for hosts deployed from this repo--paths and
> schedules stay out of Git and only materialize on the target system. Inline
> `services.duplicati-r2.targets` remains available for tests or throwaway
> setups, but it embeds the configuration in the Nix store.

Evaluate the configuration (`nix build .#nixosConfigurations.<host>`) or switch
directly, then inspect the resulting timers:

```bash
systemctl list-timers 'duplicati-r2-backup-*'
systemctl list-timers 'duplicati-r2-verify-*'
```

Use `scripts/validate-oncalendar.sh '<expr>'` to lint schedules locally before
committing them.

### Custom credential mapping

If your encrypted file uses different key names, override the mapping instead of
editing the module:

```nix
services.duplicati-r2.credentials = {
  AWS_ACCESS_KEY_ID.secret = "backup/awsAccessKeyId";
  AWS_SECRET_ACCESS_KEY.secret = "backup/awsSecretAccessKey";
  # remaining entries inherit defaults
};
```

## 4. Manual operations

- **Run a backup now:** `sudo systemctl start duplicati-r2-backup-<name>.service`
- **Check logs:** `journalctl -u duplicati-r2-backup-<name>.service`
- **Force verification:** `sudo systemctl start duplicati-r2-verify-<name>.service`
- **List snapshots:** `sudo duplicati-cli list-current "s3://$R2_BUCKET/${HOSTNAME}"`

`duplicati-cli` resolves credentials through `/etc/duplicati/r2.env`, so the
commands above must run as `root`.

## 5. Restoring files

To restore into `/tmp/restore`:

```bash
sudo bash <<'RESTORE'
set -euo pipefail
umask 077

# expose credentials to Duplicati
set -a
source /etc/duplicati/r2.env
set +a

# adjust --version / --time / --include as needed
duplicati-cli restore \
  "s3://$R2_BUCKET/${HOSTNAME}" \
  --restore-path=/tmp/restore \
  --passphrase="$DUPLICATI_PASSPHRASE"
RESTORE
```

Tidy the scratch directory when finished and scrub sensitive artifacts.

## 6. Add another folder to the backup set

1. **Decrypt the manifest to a temporary file.** The upstream secret stores
   the manifest as a JSON string under `data`, so decode it before editing:

   ```bash
   sops -d secrets/duplicati-config.json | jq '.data | fromjson' > /tmp/duplicati-config.json.tmp
   ```

2. **Edit the `targets` map.** Add a new key with the desired schedule and options, mirroring the existing entries:

   ```json
   {
     "targets": {
       "bankdata-jim-woodring": { ... },
       "photos": {
         "path": "/srv/photos",
         "onCalendar": "daily",
         "retention": "30D:1D",
         "extraArgs": ["--throttle-upload=5MB"]
       }
     }
   }
   ```

   Each target must provide an absolute `path` and a valid `OnCalendar` expression. Optional keys include `retention`, `extraArgs`, `stateDir`, and `destSubpath`.

3. **Re-wrap and re-encrypt the manifest.** Re-stringify the edited JSON,
   copy it into place, and encrypt in-place so the SOPS creation rules match
   the `secrets/` path.

   ```bash
   jq -c '{data: tostring}' /tmp/duplicati-config.json.tmp > /tmp/duplicati-config.json.wrapped
   cp /tmp/duplicati-config.json.wrapped secrets/duplicati-config.json
   sops --config .sops.yaml --encrypt --in-place secrets/duplicati-config.json
   rm /tmp/duplicati-config.json.tmp /tmp/duplicati-config.json.wrapped
   ```

4. **Refresh secrets and regenerate unit files.**

   ```bash
   sudo systemctl restart sops-install-secrets.service
   sudo systemctl start duplicati-r2-generate-units.service
   ```

5. **Run the new backup manually** (optional, but recommended) and inspect logs:

   ```bash
   sudo systemctl start duplicati-r2-backup-photos.service
   journalctl -xeu duplicati-r2-backup-photos.service
   ```

6. **Verify the timer was created.**

   ```bash
   systemctl list-timers 'duplicati-r2-backup-*'
   ```

Following these steps ensures the generator picks up the updated manifest and Duplicati immediately knows about the new folder.

## 7. Keeping the backup healthy

- Keep the manifest’s `targets` tidy--remove unused entries to keep S3
  storage minimal and timers readable.
- When rotating credentials, update `secrets/duplicati-r2.yaml` and redeploy;
  the rendered env file refreshes automatically.
- Retention can be set per target (`targets.<name>.retention`). Use `null` to
  disable retention for a specific backup.
- Verification downloads random samples. Adjust `verify.samples` or omit the
  `verify` block to disable the timer entirely.

## 8. Troubleshooting checklist

1. **Environment file missing:** `systemctl show duplicati-r2-backup-*.service -p EnvironmentFile`
   should report `/etc/duplicati/r2.env`. If it is absent, ensure the SOPS
   secret exists and the module is imported after `sops-nix`.
2. **OnCalendar rejected:** Run `scripts/validate-oncalendar.sh '<expression>'`
   locally to reproduce the validation error.
3. **Duplicati CLI errors:** Backups surface non-zero exit codes in
   `journalctl -u duplicati-r2-backup-<name>.service`. Consult the last log
   lines for the exact `duplicati-cli` message (authentication, retention, etc.).
4. **S3 endpoint issues:** Ensure the env file exposes either
   `R2_S3_ENDPOINT_URL` or `R2_ACCOUNT_ID`; the wrapper derives
   `AWS_ENDPOINT_URL` automatically.
5. **Bandwidth limits:** Use `targets.<name>.extraArgs` for flags like
   `--throttle-upload`. They are appended to the generated command.
