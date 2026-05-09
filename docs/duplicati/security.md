# Duplicati R2 Security

Threat model, secret layout, state-directory access controls, credential rotation, and the bucket lifecycle posture. This page is the reference for "is it safe to do X" questions about the duplicati pipeline.

## Threat model

| Concern                                               | Mitigation                                                                                                                                                                                                                                                                                |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Plaintext credentials at rest in Git                  | All credentials are encrypted under SOPS with the host age key (`secrets/duplicati-r2.yaml`). Plaintext only materializes at runtime under `/etc/duplicati/r2.env` (mode 0400).                                                                                                           |
| Manifest exposes paths and schedules                  | Encrypted with SOPS in binary mode (`secrets/duplicati-config.json`). Plaintext only at runtime under `/run/duplicati-r2/config.json` (mode 0400, on tmpfs).                                                                                                                              |
| Backup contents readable to anyone with R2 keys       | Duplicati encrypts every volume client-side with AES-256-CBC + HMAC-SHA256 (Encrypt-then-MAC, AES Crypt File Format v2; v3 with PBKDF2-HMAC-SHA512 KDF is opt-in via `DUPLICATI__AES_VERSION=3` on Duplicati 2.3.0.101+) keyed off `DUPLICATI_PASSPHRASE`. R2 only ever holds ciphertext. |
| Local DB metadata exposes file layout                 | `services.duplicati-r2.stateDir` defaults to `/var/lib/duplicati-r2`, mode 0700 root:root. Reader access is opt-in via `stateDirReadableBy` (POSIX ACLs, not mode broadening).                                                                                                            |
| In-flight uploads orphaned by a crash get auto-pruned | The bucket-default lifecycle rule (abort-incomplete-multipart) is removed. See [Bucket lifecycle caveat](#bucket-lifecycle-caveat).                                                                                                                                                       |

## SOPS layout

`secrets/duplicati-r2.yaml` holds the credentials in a structured YAML namespace:

```yaml
duplicati-r2:
  AWS_ACCESS_KEY_ID: ...
  AWS_SECRET_ACCESS_KEY: ...
  R2_ACCOUNT_ID: ...
  R2_API_TOKEN: ...
  R2_BUCKET: ...
  R2_S3_ENDPOINT: ...
  R2_S3_ENDPOINT_URL: ...
  R2_REGION: ...
  DUPLICATI_PASSPHRASE: ...
```

The module declares one `sops.secrets."duplicati-r2/<NAME>"` per credential, sourced from this file. A single `sops.templates."duplicati-r2-env"` concatenates them into `/etc/duplicati/r2.env`. The template carries `restartUnits = [ "duplicati-r2-generate-units.service" ]`, so any credential change automatically regenerates the env file and re-emits the units.

`secrets/duplicati-config.json` is encrypted in SOPS binary mode. The module declares it as `sops.secrets."duplicati-r2/manifest"` with `format = "binary"`, then `sops.templates."duplicati-r2-manifest.json"` writes the decrypted bytes to `/run/duplicati-r2/config.json` with the same `restartUnits`. Binary mode requires `--input-type binary --output-type binary` for inspection (see [operations.md](operations.md#manifest)).

The `.sops.yaml` rule that selects the host age key keys off the secrets path. Use `--filename-override secrets/duplicati-config.json` whenever encrypting the manifest from a non-canonical location so the recipient is set correctly.

## State directory access

The default mode for `services.duplicati-r2.stateDir` is 0700 root:root. The systemd-tmpfiles rule that creates it does not relax the base mode. Maintainer access is granted through `stateDirReadableBy`, which appends three POSIX ACL rules per listed user (the inline-mode layout nests SQLite databases at `<stateDir>/<target>/duplicati-r2-<slug>.sqlite`, so coverage is split by depth):

| Rule                                                | Effect                                                                                                                                                       |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `A+ <stateDir> - - - - u:<user>:rX,d:u:<user>:rX`   | Grants `<user>` read+traverse on the state directory itself, and sets a default ACL so files and subdirectories created directly inside inherit read access. |
| `A+ <stateDir>/* - - - - u:<user>:rX,d:u:<user>:rX` | Applies the same access ACL plus default ACL to existing per-target subdirectories so SQLite files duplicati creates inside them inherit read access.        |
| `A+ <stateDir>/*/* - - - - u:<user>:rX`             | Applies the access ACL to SQLite files already present in per-target subdirectories at activation time.                                                      |

Result: the directory remains `drwx------` at the mode level; an `ls -l` shows a `+` indicator denoting the ACL extension. Duplicati continues to create the SQLite files as root, but listed users can `cat` them and open them read-only with `sqlite3 'file:<path>?mode=ro&immutable=1'`.

Reasons not to broaden the base mode:

- The default permission is what stops other unprivileged accounts on the host from reading backup metadata.
- ACLs survive `tmpfiles` re-runs because the rule is `A+` (additive) rather than `A` (replace).
- Using a group like `wheel` would also work but grants access to anyone with sudo. The ACL-by-username path is least-privilege.

## Credential rotation

Rotating R2 access pairs and most other entries is safe; the env file refreshes on the next deploy:

```bash
nix develop -c sops -i secrets/duplicati-r2.yaml
nixos-rebuild switch --flake .#<host>     # or ./build.sh
```

Two specific rotations have additional considerations.

### R2 API tokens

Issue the new token in Cloudflare, paste the new `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`R2_API_TOKEN` into `secrets/duplicati-r2.yaml`, redeploy. The next backup uses the new credentials. Revoke the old token only after a successful backup confirms the new one works.

### Duplicati passphrase

Do not rotate. The passphrase is per-archive: changing it strands every existing backup because they were encrypted under the old key. The only safe "rotation" is to start a new bucket prefix (or new bucket) with a new passphrase, run a fresh full backup, and keep the old archive read-only for the duration of any required restore window.

## Bucket lifecycle caveat

Cloudflare R2 attaches a default lifecycle rule to new buckets: `AbortIncompleteMultipartUpload` after seven days. The rule sweeps multipart upload sessions that were started but never finalized, freeing the per-part storage. Completed objects are never affected.

This is a real data-loss vector in this pipeline. Duplicati uploads volumes larger than the multipart threshold via S3 multipart. If the duplicati process is interrupted between the final `UploadPart` and `CompleteMultipartUpload`, the parts sit in the multipart-upload state. The local DB still tracks the volume in `Remotevolume.State='Uploaded'` (never advanced to `Verified`), so duplicati expects the volume to be present on the next run. After seven days the lifecycle sweeps the parts, the volume never becomes a completed object, and any blocks contained in that volume become unrecoverable if the source data is no longer available.

The rule is removed on the duplicati R2 bucket. Confirm at any time:

```bash
eval "$(sops -d secrets/duplicati-r2.yaml | yq -r '.["duplicati-r2"] | to_entries | .[] | "export \(.key)=\(.value | @sh)"')"
curl -sS "$R2_S3_ENDPOINT_URL/$R2_BUCKET?lifecycle" \
  --aws-sigv4 'aws:amz:auto:s3' \
  --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY"
```

A response of `<LifecycleConfiguration></LifecycleConfiguration>` (empty body) means no rules are active.

If reinstating the rule is ever necessary, choose a window that comfortably outlasts the longest expected outage of the source data plus a margin (90 days is the recommended floor). Set it via `PUT <bucket>?lifecycle` with the standard `LifecycleConfiguration` XML.

## Multipart upload hygiene

With the lifecycle rule removed, orphan multipart sessions accumulate silently. They do not appear in `ListObjects` or the Cloudflare dashboard's object list, but the per-part storage bills toward the bucket. Schedule a periodic inventory:

```bash
eval "$(sops -d secrets/duplicati-r2.yaml | yq -r '.["duplicati-r2"] | to_entries | .[] | "export \(.key)=\(.value | @sh)"')"

# Inventory: list any in-progress multipart uploads.
curl -sS "$R2_S3_ENDPOINT_URL/$R2_BUCKET?uploads" \
  --aws-sigv4 'aws:amz:auto:s3' \
  --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY"
```

The response is an XML `ListMultipartUploadsResult`. Each `<Upload>` entry includes a `<Key>`, a `<UploadId>`, and an `<Initiated>` timestamp. Anything older than the longest plausible duplicati run is a candidate for cleanup:

```bash
curl -sS -X DELETE \
  "$R2_S3_ENDPOINT_URL/$R2_BUCKET/<key>?uploadId=<UploadId>" \
  --aws-sigv4 'aws:amz:auto:s3' \
  --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY"
```

Treat aborts as final: the part data is gone after `AbortMultipartUpload`. Cross-check the local duplicati DB before aborting (a `Remotevolume` row with `State='Uploaded'` indicates duplicati still expects the volume; resolve by re-running `repair`, which either completes the upload from local source or reports it unrecoverable).

## Audit checklist

A quarterly audit covers everything noted above:

1. Confirm `secrets/duplicati-r2.yaml` and `secrets/duplicati-config.json` decrypt under the current age key.
2. Verify `services.duplicati-r2.stateDirReadableBy` matches the maintainer set; remove stale entries.
3. Inspect bucket lifecycle (`GET ?lifecycle`) and confirm no abort-multipart rule has been re-attached.
4. List in-progress multipart uploads; abort anything older than the longest expected backup.
5. Run `duplicati-cli test <dest> --samples=200` against each active target, or rely on the verify timer's logs.
6. Confirm the duplicati passphrase has not changed since the last audit by decrypting `secrets/duplicati-r2.yaml` and diffing against the previous known-good value.
