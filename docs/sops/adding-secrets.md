# Adding a Secret

A secret is an encrypted YAML file under `secrets/`, one declaration per consumed key in the module that owns it, and a consumer that reads the runtime path.
The policy and the age key are in [sops-nix Usage](README.md).

1. Confirm the recipient exists in `.sops.yaml`.

2. Create or edit the encrypted file:

   ```bash
   sops secrets/<service>.yaml
   ```

3. Start ordinary service credentials from the plaintext template `secrets/secret.yaml.example`: a small YAML document with flat, top-level `snake_case` keys.
   The `sops:` metadata block is never added by hand; SOPS adds and maintains it after encryption.

   ```yaml
   # secrets/<service>.yaml
   # Edit with: sops secrets/<service>.yaml
   # Do not add the sops: metadata block manually. SOPS adds it after encryption.

   api_token: "<secret>"
   client_id: "<secret>"
   client_secret: "<secret>"
   ```

4. Declare each consumed key explicitly in the owning module, with `key` set to the YAML key name even where it matches.
   The runtime secret name often uses slashes or hyphens, while the YAML key stays simple:

   ```nix
   {
     config,
     lib,
     metaOwner,
     secretsRoot,
     ...
   }:
   let
     serviceSecretFile = secretsRoot + "/<service>.yaml";
     serviceSecretExists = builtins.pathExists serviceSecretFile;
     ownerName = metaOwner.username;
   in
   {
     config = lib.mkIf serviceSecretExists {
       sops.secrets."<service>/api-token" = {
         sopsFile = serviceSecretFile;
         format = "yaml";
         key = "api_token";
         path = "/run/secrets/<service>/api-token";
         mode = "0400";
         owner = ownerName;
       };

       # One declaration like this per consumed key: client_id, client_secret, ...
     };
   }
   ```

5. A Home Manager module uses the same YAML shape and explicit `key` selectors, sets `path` under the user's home directory, and omits `owner` unless it needs a non-default owner.

6. Consumers reference the runtime material through `.path`, `config.sops.placeholder`, or a `sops.templates` output, and never read decrypted values at evaluation time.

7. Nested YAML is only for an owning module that expects a slash-separated selector, such as `duplicati-r2/AWS_ACCESS_KEY_ID`.
   `key = ""` is only for a consumer that needs the whole decrypted YAML file instead of one key.

8. Commit only the encrypted file under `secrets/`, with explicit `mode`, `owner`, and, where needed, `group` on every declaration, then run the validation suite in [Reference](../architecture/06-reference.md#validation).

## Font archives

Keep plaintext archives outside the checkout while packing or encrypting fonts.
The MonoLisa and Windows/Office installers decrypt archives at runtime, keeping plaintext font files out of the Nix store.
The Windows/Office service streams decryption from the encrypted store files using the host's age identity.
Its archive parts are not declared as runtime SOPS secrets, so decrypted archives do not remain resident after installation.

For Windows/Office updates, retain the archive's `fonts/` directory, provenance, licenses, and `SHA256SUMS` manifest.
Regenerate the manifest after changing the payload, excluding the manifest itself.
Split the compressed archive into parts before encryption to stay below GitHub's file size limit.
The installer declares the required parts in `modules/hosts/common/office-fonts.nix`; update that list if the archive needs more parts.
Encrypt each part using the repository's SOPS policy, with plaintext files outside the checkout:

```sh
split -b 64M -d -a 2 /path/outside/checkout/windows-office.tar.zst \
  /path/outside/checkout/windows-office.tar.zst.part-
for part in /path/outside/checkout/windows-office.tar.zst.part-*; do
  target="secrets/fonts/$(basename "$part")"
  sops encrypt --input-type binary --output-type binary \
    --filename-override "$target" --output "$target" "$part"
done
```

Commit and push the encrypted archive in the secrets repository, then update the parent repository's submodule pointer.
After switching the NixOS configuration, verify the installer and font selection:

```sh
systemctl status windows-office-fonts.service
fc-match 'Aptos'
fc-match 'Georgia Pro'
```
