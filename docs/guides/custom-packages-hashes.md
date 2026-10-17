# Custom package hashes

Every fetcher and vendored dependency set in a package pins a hash, found by building once with a placeholder.
Builds go through a host's `pkgs`, as [Building an overlay package](custom-packages-overlays.md#building-an-overlay-package) shows.

## Source hash

For `fetchFromGitHub`, `fetchurl`, and `fetchzip`:

1. Set an invalid placeholder hash:

   ```nix
   hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
   ```

2. Build the package through an overlay-aware host `pkgs`:

   ```sh
   nix build "path:.#nixosConfigurations.<host>.pkgs.my-package"
   ```

3. Copy the `got:` hash from the error message into the file.

`nix-prefetch-github` computes the same hash without a build:

```sh
nix-prefetch-github owner repo --rev v1.0.0
```

## Cargo hash

1. Set an invalid placeholder:

   ```nix
   cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
   ```

2. Build, and copy the `got:` hash from the error.

`cargoLock.lockFile` with a path inside `${src}` fetches the source during evaluation, which breaks offline and pure evaluation, so packages always use `cargoHash`.

A package with `passthru.updateScript` updates its cargo hash through `updater.calculate_dependency_hash` from `scripts/updater/`:

1. Load `packages/<name>/hashes.json`.
2. Fetch the latest upstream version.
3. Recalculate `srcHash`.
4. Write a temporary dummy `cargoHash`.
5. Build `.#nixosConfigurations.<host>.pkgs.<name>` and extract the `got:` hash.
6. Save the final `hashes.json`.

## Vendor hash

Go packages follow the cargo hash workflow for `vendorHash`: placeholder, build, copy the correct hash.

## Header-aware source hashes

A vendor download that needs browser-like request headers is hashed with `updater.calculate_url_hash`, given an explicit `headers` mapping, instead of `nix store prefetch-file`.
The helper downloads the file with those headers and hashes it with `nix hash file --sri`, which matches `fetchurl` file-hash semantics.

## Hash mismatches

`No such file or directory` for a vendor staging path, such as `<name>-vendor-staging`, means the hash in the file does not match the one Nix computed.
The correct vendor tree is still in the store, so hash it and copy the output into `cargoHash` or `vendorHash`:

```sh
nix hash path --type sha256 --sri /nix/store/<hash>-<name>-vendor-staging
```

## Faster updates

- Save the `got:` hash as soon as Nix prints it, rather than re-running the placeholder build.
- Keep `~/.cache/cargo/registry` and `~/.cache/cargo/git` between updates, so dependency fetches are faster.
- Track past `got:` values, which shows whether the dependency graph changed or only the source revision.
