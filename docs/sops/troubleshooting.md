# sops-nix Troubleshooting

Safe editing procedures are in [sops-nix Usage](README.md#editing-encrypted-files-safely).

## `no secret material for ...`

Declarations are guarded with `pathExists`, so a missing encrypted file leaves its secrets undeclared.
Check that the encrypted file exists under `secrets/`, with the submodule initialized.

## `Unknown recipient` while editing

The key is not in the `.sops.yaml` policy.
Add it to `.sops.yaml`.

## `Permission denied` reading a secret

sops-nix enforces the declared ownership strictly.
Adjust the `owner` and `group` fields in the declaring module.

## `no matching creation rules found`

The file path is outside `secrets/`.
Move the file under `secrets/`, where every path is covered regardless of extension.

## `sops metadata not found`

The file is plaintext or corrupted.
Re-encrypt plaintext with `sops -e -i <file>`, or restore a corrupted file from backup.

## File truncated to 0 bytes

A shell redirect (`>`) truncated the file before the command ran.
Restore it from backup, and encrypt in place with `sops -e -i` as [Programmatic / Scripted Editing](README.md#programmatic--scripted-editing) shows.
