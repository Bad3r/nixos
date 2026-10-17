# Custom Packages Style Guide

Conventions for in-tree packages at `packages/<name>/default.nix`.
The app module that installs one follows the [Apps Module Style Guide](apps-module-style-guide.md).

- [Source builds](custom-packages-source-builds.md): Rust, Go, and Python templates.
- [Binaries and scripts](custom-packages-binaries-and-scripts.md): binary download and shell wrapper templates.
- [Overlays](custom-packages-overlays.md): exposing a package as `pkgs.<name>` or as a flake output.
- [Hashes](custom-packages-hashes.md): source, cargo, and vendor hashes and the updater helpers.

## When to create a custom package

- The software is not available in nixpkgs or one of the other inputs.
- The nixpkgs version is outdated or broken, and upstream has not merged a fix.
- The package needs build flags, patches, or configuration not suitable for upstream.

When nixpkgs gains a package that replaces a custom one, switch the app module to the nixpkgs package and delete `packages/<name>/` together with its `modules/custom-overlays/<name>.nix` entry.
A replaced package is deleted, never kept as an underscore-prefixed copy.

## File structure

- The directory name is lowercase and hyphenated, matching the package's `pname`.
- `default.nix` stands alone unless patches or other files are required, as in `packages/dnsleak/`.
- `hashes.json` holds several update-managed pins, such as `version`, `srcHash`, and `cargoHash`, as in `packages/searchfox-cli/`.
- `update.py` updates the package mechanically from upstream release metadata, exposed with `passthru.updateScript = ./update.py;`.
- Patches sit next to `default.nix`, as in `packages/wfuzz/`.

`update.py` starts with a `nix-shell` shebang, so the script stays runnable on its own:

```python
#!/usr/bin/env nix-shell
#! nix-shell -i python3 --packages python3
```

Lix implements no `#!/usr/bin/env nix` shebang, so the CppNix `#! nix shell ...` form fails with `is not a recognised command`.
The shebang requests `python3`, while `nix` and `nix-prefetch-url` come from the ambient Lix that runs it.
An updater that invokes another command directly adds its package to `--packages`, such as `yq-go` for `packages/webcrack/update.py`; otherwise it depends on the caller's `PATH`.

`--packages` resolves `<nixpkgs>` from the Nix search path rather than from this flake's inputs.
Hosts configured by this repository set that path through `nix.nixPath` in `modules/base/nixpkgs.nix`, which also disables channels.
On an unconfigured machine the updaters fail with `file 'nixpkgs' was not found in the Nix search path`.
Pinning the flake input instead does not work, because Lix `nix-shell` rejects the CppNix `--inputs-from` flag.

## Required meta fields

Every package sets these:

| Field         | Description             | Example                                |
| ------------- | ----------------------- | -------------------------------------- |
| `description` | One-line summary        | `"Deobfuscate obfuscator.io, ..."`     |
| `homepage`    | Project landing page    | `"https://github.com/j4k0xb/webcrack"` |
| `license`     | SPDX license            | `lib.licenses.mit`                     |
| `mainProgram` | Primary executable name | `"webcrack"`                           |
| `platforms`   | Supported platforms     | `lib.platforms.linux`                  |

Optional but recommended:

| Field             | Description                                 |
| ----------------- | ------------------------------------------- |
| `changelog`       | Release notes URL                           |
| `longDescription` | Multi-line description for complex packages |
| `maintainers`     | Upstream nixpkgs maintainers, if any        |

## App modules

| Aspect        | Custom package                | App module                        |
| ------------- | ----------------------------- | --------------------------------- |
| Location      | `packages/<name>/default.nix` | `modules/apps/<name>.nix`         |
| Purpose       | Build the software            | Enable and configure it           |
| Output        | Derivation                    | NixOS module                      |
| Enable option | None                          | `programs.<name>.extended.enable` |

A package gets a corresponding app module in `modules/apps/<name>.nix` when:

- It is a user-facing application.
- Hosts should enable or disable it declaratively.
- It needs unfree allowlisting or extra configuration.
- It is host-visible tooling, such as a shell helper or system-management script like `modules/apps/sss-nix-repair.nix`.

A package used only in devshells, or a library or build tool, needs no app module.
Every app module needs a row, as [App registry](apps-module-registry.md) describes.

## Validation

Before committing a new package, confirm that:

- `packages/<name>/default.nix` sets every required meta field, and `passthru.updateScript = ./update.py;` when an updater exists.
- A package that must be `pkgs.<name>` has its overlay module in `modules/custom-overlays/<name>.nix`.
- New files are staged or intent-to-added before flake or import-tree evaluation.
- A user-facing or host-visible package has an app module, a baseline row, and host rows only for real divergences.

These commands pass from the repository root, the updater ones only when an updater exists:

```sh
nix build "path:.#nixosConfigurations.<host>.pkgs.<name>"
./packages/<name>/update.py --force
script=$(nix eval --accept-flake-config --raw "path:.#nixosConfigurations.<host>.pkgs.<name>.passthru.updateScript"); "$script" --force
nix develop path:. --no-write-lock-file -c hook-apps-catalog-sync
nix flake check path:. --accept-flake-config
```

`hook-apps-catalog-sync` matters when app catalog files changed, and the full flake check for structural package or module changes.

## Reference implementations

| Package type     | Reference                                  |
| ---------------- | ------------------------------------------ |
| Go               | `packages/age-plugin-fido2prf/default.nix` |
| Python           | `packages/wappalyzer-next/default.nix`     |
| Rust             | `packages/searchfox-cli/default.nix`       |
| Binary download  | `packages/charles/default.nix`             |
| Shell wrapper    | `packages/dnsleak/default.nix`             |
| Complex Java     | `packages/malimite/default.nix`            |
| Electron wrapper | `packages/raindrop/default.nix`            |
