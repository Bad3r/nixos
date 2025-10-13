# Duplicati → Cloudflare R2 Backups

This repository ships a NixOS module that wires `duplicati-cli` up to Cloudflare
R2 using the S3-compatible endpoint. It provisions:

- a SOPS-managed dotenv at `/etc/duplicati/r2.env` with the R2 credentials and
  encryption passphrase
- a oneshot service/timer pair (`duplicati-r2-backup.{service,timer}`) that runs
  `duplicati-cli backup`
- a verification job (`duplicati-r2-verify.{service,timer}`) that samples
  archives with `duplicati-cli test`
- the Duplicati web interface (listening on `localhost:8200`) for ad-hoc
  inspection or GUI restores

## 1. Encrypt the credentials

Populate `secrets/duplicati-r2.yaml` and encrypt it in place:

```bash
nix develop -c sops -e -i secrets/duplicati-r2.yaml
```

The secret uses YAML with the following keys:

```yaml
r2:
  awsAccessKeyId: ...
  awsSecretAccessKey: ...
  accountId: 28375972d83d8943ad779dc380fea05d
  s3EndpointHost: 28375972d83d8943ad779dc380fea05d.r2.cloudflarestorage.com
  s3EndpointUrl: https://28375972d83d8943ad779dc380fea05d.r2.cloudflarestorage.com
  apiToken: <r2-api-token>
  bucket: duplicati-nixos-backups
  passphrase: change-me
```

> The passphrase is mandatory—Duplicati refuses to run encrypted backups without
> it. Rotate it with `sops -d` + `openssl rand -base64 32` when needed.

## 2. Host configuration

The refactored module reads backup policy from a single
`secrets/duplicati-config.yaml.example` file. An example:

```json
{
  "hostname": "system76",
  "bucket": "duplicati-nixos-backups",
  "stateDir": "/var/lib/duplicati-r2",
  "environmentFile": "/etc/duplicati/r2.env",
  "targets": [
    {
      "path": "/bankData/Jim Woodring",
      "retention": "1Y",
      "schedule": "0 3 * * *"
    }
  ],
  "verify": {
    "schedule": "0 6 * * *",
    "samples": 200
  }
}
```

Opt a host in with:

```nix
services.duplicati-r2 = {
  enable = true;
  configFile = inputs.secrets + "/duplicati-config.yaml.example";
};
```

Deploy with the usual workflow (`nix build .#nixosConfigurations.system76` +
`./build.sh --host system76`). After the switch you should see the timers:

```bash
systemctl list-timers 'duplicati-r2*'
```

The web UI is reachable on `https://localhost:8200` (default credentials are
empty until you set a web password via the GUI).

## 3. Manual operations

- **Run now:** `sudo systemctl start duplicati-r2-backup.service`
- **Check logs:** `journalctl -u duplicati-r2-backup.service`
- **Force verification:** `sudo systemctl start duplicati-r2-verify.service`
- **List snapshots:** `sudo duplicati-cli list-current "s3://$R2_BUCKET/${HOSTNAME}"`

`duplicati-cli` resolves credentials through `/etc/duplicati/r2.env`, so the
commands above must run as `root`.

## 4. Restoring files

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

## 5. Keeping the backup healthy

- Backups and verification schedules live in `secrets/duplicati-config.yaml.example`; copy it to a
  host-specific secret if you need to rotate schedules outside the repo.
  Update cron expressions there and redeploy to reschedule timers.
- Retention can be set per target (`targets[].retention`) or via the optional
  top-level `defaultRetention`.
- Verification downloads random samples. Adjust `verify.samples` or remove the
  section to disable the timer entirely.
- When rotating credentials, re-encrypt `secrets/duplicati-r2.env` and redeploy;
  the systemd units reload the updated env file automatically.

## 6. Troubleshooting checklist

1. `services.duplicati-r2` requires at least one entry under `targets`. Missing
   `path` or `schedule` values will raise evaluation errors.
2. `sudo cat /etc/duplicati/r2.env` should match the encrypted secret (file mode
   0400, owned by the backup user you configured).
3. Use `duplicati-cli help backup` / `duplicati-cli help test` for the full list
   of supported options.
4. Cloudflare R2 requires disabling host prefix injections and chunked uploads;
   the module bakes `s3-ext-disablehostprefixinjection=true` and
   `s3-disable-chunk-encoding=true` into the destination URL automatically.
