# NixOS Configuration

A NixOS configuration using the **Dendritic Pattern** - an organic configuration growth pattern with automatic module discovery.

Based on the golden standard from [mightyiam/infra](https://github.com/mightyiam/infra).

## Automatic import

Nix files (they're all flake-parts modules) are automatically imported.
Nix files prefixed with an underscore are ignored.
No literal path imports are used.
This means files can be moved around and nested in directories freely.

> [!NOTE]
> This pattern has been the inspiration of [an auto-imports library, import-tree](https://github.com/vic/import-tree).

## Module Aggregators

This flake exposes two mergeable aggregators:

- `flake.nixosModules`: NixOS modules (freeform, nested namespaces allowed)
- `flake.homeManagerModules`: Home Manager modules (freeform; with `base`, `gui`, and per-app under `apps`)

Modules register themselves under these namespaces (e.g., `flake.nixosModules.workstation`, `flake.homeManagerModules.base`).
Composition uses named references, for example:

```nix
{ config, ... }:
{
  configurations.nixos.myhost.module = {
    imports = with config.flake.nixosModules; [ base workstation ];
  };
}
```

Use `lib.hasAttrByPath` + `lib.getAttrFromPath` when selecting optional modules to avoid ordering issues.

### Roles and App Composition

- Roles are assembled from per-app modules under `flake.nixosModules.apps`, using `config.flake.lib.nixos.getApps` / `getApp` for lookups.
- Avoid lexical `with` over `config.flake.nixosModules.apps`; the helper namespace keeps evaluation pure and consistent.
- Import roles via `flake.nixosModules.roles.<name>` (for example, `.dev`, `.media`, `.net`).

Example host composition using the role namespace:

```nix
{ config, ... }:
{
  configurations.nixos.system76.module = {
    imports =
      (with config.flake.nixosModules; [
        workstation
      ])
      ++ [
        config.flake.nixosModules.roles.dev
      ];
  };
}
```

For a complete, type-correct composition plan and guidance, see
`docs/RFC-001.md`.

## Development Shell

Enter the development shell:

```bash
nix develop
```

Useful commands:

- `nix fmt` – format files
- `pre-commit run --all-files` – run all hooks
- `update-input-branches` – rebase vendored inputs, push inputs/\* branches, and commit updated gitlinks. The helper keeps `inputs/nixpkgs` as a blobless partial clone; set `HYDRATE_NIXPKGS=1` to hydrate temporarily or `KEEP_WORKTREE=1` to leave a checked-out tree intact.

The `build.sh` helper refuses to run if the git worktree is dirty (tracked changes, staged changes, or untracked files) to keep builds reproducible. Override with `--allow-dirty` or `ALLOW_DIRTY=1` only when you know what you’re doing.

## Adding a new secret with sops-nix

1. **Encrypt the payload** – run `sops secrets/<name>.yaml` (or `sops -e -i …`) so the file is stored as ciphertext. The canonical `.sops.yaml` in this repo already targets everything under `secrets/`.
2. **Declare the secret in Nix** – add an entry under `sops.secrets."<namespace>/<name>"` (system or Home Manager). Point `sopsFile` to the encrypted file, set `key` when selecting a single YAML attribute, and write the decrypted material to a runtime path using `%r`.
3. **Consume via the module API** – reference `config.sops.secrets."<namespace>/<name>".path` (or `placeholder`) from services, wrappers, or templates. Never read secrets at evaluation time.

Example (Context7 MCP key for Codex):

```nix
sops.secrets."context7/api-key" = {
  sopsFile = ./../../secrets/context7.yaml;
  key = "context7_api_key";
  path = "%r/context7/api-key";
  mode = "0400";
};
```

The Codex module wraps the decrypted path in a small script and only enables the MCP server when the secret exists, keeping evaluation pure while allowing runtime access.

## Generated files

The following files in this repository are generated and checked
using [the _files_ flake-parts module](https://github.com/mightyiam/files):

- `.actrc`
- `.github/workflows/check.yml`
- `.gitignore`
- `.sops.yaml`
- `README.md`

## Flake inputs for deduplication are prefixed

Some explicit flake inputs exist solely for the purpose of deduplication.
They are the target of at least one `<input>.inputs.<input>.follows`.
But what if in the future all of those targeting `follows` are removed?
Ideally, Nix would detect that and warn.
Until that feature is available those inputs are prefixed with `dedupe_`
and placed in an additional separate `inputs` attribute literal
for easy identification.

## Trying to disallow warnings

This at the top level of the `flake.nix` file:

```nix
nixConfig.abort-on-warn = true;
```

> [!NOTE]
> It does not currently catch all warnings Nix can produce, but perhaps only evaluation warnings.
