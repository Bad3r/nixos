# Custom Packages Style Guide

This guide defines the conventions for adding custom packages under `packages/<name>/default.nix`. Use it alongside the existing packages as references, and see [Apps Module Style Guide](apps-module-style-guide.md) for the corresponding app module pattern.

## When to Create a Custom Package

Create a custom package when:

- The software is not available in nixpkgs or one of the other inputs
- The nixpkgs version is outdated or broken and upstream hasn't merged a fix
- You need custom build flags, patches, or configuration not suitable for upstream

When a package becomes available in nixpkgs, switch the app module to the nixpkgs package, remove or disable its `modules/custom-overlays/<name>.nix` entry, and deprecate the old package file by prefixing it with `_` (e.g., `_default.nix`) plus a short deprecation comment.

## File Structure

Store each custom package at:

```
packages/<name>/default.nix
```

Use lowercase, hyphenated names matching the package's `pname`. Keep the directory flat with just `default.nix` unless patches or additional files are required:

```
packages/
├── age-plugin-fido2prf/
│   └── default.nix
├── searchfox-cli/
│   ├── default.nix
│   ├── hashes.json
│   └── update.py
└── malimite/
    ├── default.nix
    └── fix-classpath.patch
```

Use `hashes.json` when a package has multiple update-managed pins, such as `version`, `srcHash`, and `cargoHash`. Add `update.py` when the package can be updated mechanically from upstream release metadata. Expose it from the derivation with `passthru.updateScript = ./update.py;`.

## Package Template

Use the appropriate builder for your package type. All packages must include a `meta` attribute set.

### Rust Package (buildRustPackage)

```nix
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
}:

let
  pin = lib.importJSON ./hashes.json;
in
rustPlatform.buildRustPackage rec {
  pname = "example-tool";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "example";
    repo = "example-tool";
    rev = "v${version}";
    hash = pin.srcHash;
  };

  cargoHash = pin.cargoHash;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  passthru.updateScript = ./update.py;

  meta = {
    description = "Short one-line description";
    homepage = "https://example.com";
    license = lib.licenses.mit;
    mainProgram = "example-tool";
    platforms = lib.platforms.linux;
  };
}
```

### Go Package (buildGoModule)

```nix
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "example-go";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = "example-go";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  vendorHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";

  ldflags = [ "-s" "-w" ];

  meta = {
    description = "Short one-line description";
    homepage = "https://example.com";
    license = lib.licenses.mit;
    mainProgram = "example-go";
    platforms = lib.platforms.unix;
  };
}
```

### Python Package (buildPythonApplication)

```nix
{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonApplication rec {
  pname = "example-py";
  version = "1.0.0";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "example";
    repo = "example-py";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  propagatedBuildInputs = with python3Packages; [
    requests
  ];

  doCheck = false;  # Only if upstream has no tests

  meta = {
    description = "Short one-line description";
    homepage = "https://example.com";
    license = lib.licenses.mit;
    mainProgram = "example-py";
    platforms = lib.platforms.linux;
  };
}
```

### Binary Download (stdenvNoCC)

For pre-built binaries with multi-platform support:

```nix
{
  lib,
  stdenvNoCC,
  fetchzip,
  makeWrapper,
}:

let
  version = "1.0.0";

  downloads = {
    x86_64-linux = {
      url = "https://example.com/releases/${version}/example-linux-x64.zip";
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
    aarch64-linux = {
      url = "https://example.com/releases/${version}/example-linux-arm64.zip";
      sha256 = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
    };
  };

  platform =
    downloads.${stdenvNoCC.hostPlatform.system}
      or (throw "example: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "example";
  inherit version;

  src = fetchzip {
    inherit (platform) url sha256;
    stripRoot = false;
  };

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src/example" "$out/bin/example"
    runHook postInstall
  '';

  meta = {
    description = "Short one-line description";
    homepage = "https://example.com";
    license = lib.licenses.unfreeRedistributable;
    mainProgram = "example";
    platforms = builtins.attrNames downloads;
  };
}
```

### Shell Wrapper (writeShellApplication)

For simple shell scripts with runtime dependencies:

```nix
{
  lib,
  writeShellApplication,
  curl,
  jq,
}:

writeShellApplication {
  name = "example-script";

  runtimeInputs = [
    curl
    jq
  ];

  # NOTE: The /* bash */ annotation enables treesitter language injection
  # for proper syntax highlighting and LSP support (via otter.nvim)
  text = /* bash */ ''
    echo "Example script"
    curl -s https://api.example.com | jq .
  '';

  meta = {
    description = "Short one-line description";
    homepage = "https://example.com";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
```

## Required Meta Fields

Every package must include these meta fields:

| Field         | Description             | Example                              |
| ------------- | ----------------------- | ------------------------------------ |
| `description` | One-line summary        | `"System76 EC tool for fan control"` |
| `homepage`    | Project landing page    | `"https://github.com/system76/ec"`   |
| `license`     | SPDX license            | `lib.licenses.mit`                   |
| `mainProgram` | Primary executable name | `"system76_ectool"`                  |
| `platforms`   | Supported platforms     | `lib.platforms.linux`                |

Optional but recommended:

| Field             | Description                                 |
| ----------------- | ------------------------------------------- |
| `changelog`       | Release notes URL                           |
| `longDescription` | Multi-line description for complex packages |
| `maintainers`     | Upstream nixpkgs maintainers if applicable  |

## Registering in an Overlay

User-facing in-tree packages are exposed through one overlay module per package under `modules/custom-overlays/`. Add a file named after the package:

```nix
_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."my-new-package".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "my-new-package" = final.callPackage ../../packages/my-new-package { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."my-new-package" = Overlay;
}
```

`modules/hosts/common/custom-overlays-base.nix` imports every module registered under `flake.customOverlays.*`. Each overlay gates itself on the matching app option, so the package is added to `pkgs` only when the app is enabled:

```nix
programs."my-new-package".extended.enable = true;
```

Use a custom overlay only for packages that must exist in `pkgs` for host builds or app modules. If a custom package is used only inside one module and does not need a reusable `pkgs.<name>` attribute, a local `pkgs.callPackage ../../packages/<name> { }` inside that module may be enough.

After registration the package is available as `pkgs.my-new-package` on every host where the app is enabled. For the managed hosts, the common baseline lives in `modules/hosts/common/apps-enable.nix`, and host-specific divergences live in `modules/<host>/apps-enable.nix`.

For non-user-facing derivations exposed as flake outputs, register them through a `perSystem` module under `modules/packages/` instead:

```nix
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.my-tool = pkgs.callPackage ../../packages/my-tool { };
    };
}
```

## Hash Fetching Workflow

### Source Hash (fetchFromGitHub, fetchurl, fetchzip)

1. Set an invalid placeholder hash:

   ```nix
   hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
   ```

2. Attempt to build the package through an overlay-aware host `pkgs`:

   ```bash
   nix build .#nixosConfigurations.<host>.pkgs.my-package
   ```

   Overlay-backed packages are not exposed as top-level flake outputs, so `nix build .#my-package` will fail with `does not provide attribute packages.x86_64-linux.my-package`. Always go through `nixosConfigurations.<host>.pkgs.<name>` to apply host overlays. If this is a new app module or overlay module, mark the new files as tracked first:

   ```bash
   git add -N packages/my-package/default.nix modules/apps/my-package.nix modules/custom-overlays/my-package.nix
   ```

3. Copy the `got:` hash from the error message into your file.

Alternatively, use `nix-prefetch-github`:

```bash
nix-prefetch-github owner repo --rev v1.0.0
```

### Cargo Hash (Rust packages)

1. Set an invalid placeholder:

   ```nix
   cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
   ```

2. Attempt to build and copy the `got:` hash from the error.

**Important:** Do not use `cargoLock.lockFile` with a path inside `${src}` as this requires the source to be fetched during evaluation, breaking offline/pure evaluation. Always use `cargoHash`.

For packages with `passthru.updateScript`, prefer implementing the cargo hash update with `scripts/updater.calculate_dependency_hash`. The usual flow is:

1. Load `packages/<name>/hashes.json`
2. Fetch the latest upstream version
3. Recalculate `srcHash`
4. Write a temporary dummy `cargoHash`
5. Build `.#nixosConfigurations.system76.pkgs.<name>` and extract the `got:` hash
6. Save the final `hashes.json`

### Vendor Hash (Go packages)

Same workflow as cargoHash--use placeholder, build, copy the correct hash.

### Header-Aware Source Hashes

For vendor downloads that require browser-like request headers, call
`scripts/updater.calculate_url_hash` with an explicit `headers` mapping instead
of `nix store prefetch-file`. The helper downloads the file with those headers
and hashes the local file with `nix hash file --sri`, which matches `fetchurl`
file-hash semantics.

### Troubleshooting Hash Mismatches

If you see `No such file or directory` for a vendor staging path (e.g., `<name>-vendor-staging`), the hash in your file doesn't match what Nix computed. The correct vendor tree still exists in the store:

```bash
# Find and hash the vendor staging directory
nix hash path --type sha256 --sri /nix/store/<hash>-<name>-vendor-staging
```

Copy the output into `cargoHash` or `vendorHash` in your derivation.

### Tips for Efficient Hash Updates

- **Capture the mismatch once:** When Nix prints the `got:` hash, save it immediately. Never re-run the placeholder build unnecessarily.
- **Keep caches warm:** Preserve `~/.cache/cargo/registry` and `~/.cache/cargo/git` between updates so dependency fetches are faster.
- **Use binary caches:** Extra Nix cache endpoints reduce time spent downloading toolchains.
- **Archive previous hashes:** Tracking past `got:` values helps identify when the dependency graph genuinely changed versus just the source revision.

## Relationship to App Modules

Custom packages and app modules serve different purposes:

| Aspect        | Custom Package                | App Module                        |
| ------------- | ----------------------------- | --------------------------------- |
| Location      | `packages/<name>/default.nix` | `modules/apps/<name>.nix`         |
| Purpose       | Build the software            | Enable and configure it           |
| Output        | Derivation                    | NixOS module                      |
| Enable option | None                          | `programs.<name>.extended.enable` |

### When to Create an App Module

Create a corresponding app module in `modules/apps/<name>.nix` when:

- The package is a user-facing application
- Users should be able to enable/disable it declaratively
- The package needs unfree allowlisting or extra configuration
- The package is host-visible tooling such as a shell helper or system-management script (e.g., `modules/apps/sss-pass-gpg-bootstrap.nix`, `modules/apps/sss-nix-repair.nix`)

Skip the app module when:

- The package is only used in devshells
- The package is a library or build tool

The `apps-catalog-sync` pre-commit hook (`modules/meta/hooks/apps-catalog-sync.nix`) enforces that every app module under `modules/apps/` is represented in the app catalog. Add the shared default to `modules/hosts/common/apps-enable.nix` with `lib.mkOverride 1100`, then add entries to `modules/<host>/apps-enable.nix` only when a host must diverge from the common baseline.

See [Apps Module Style Guide](apps-module-style-guide.md) for the app module format.

## Validation Checklist

Before committing a new package:

- [ ] File exists at `packages/<name>/default.nix`
- [ ] `passthru.updateScript = ./update.py;` is present when the package has a mechanical updater
- [ ] All required meta fields are present
- [ ] Package is registered in `modules/custom-overlays/<name>.nix` when it must be exposed as `pkgs.<name>`
- [ ] New files are staged or intent-to-added before flake/import-tree evaluation
- [ ] App module created if user-facing or host-visible (see [Apps Module Style Guide](apps-module-style-guide.md))
- [ ] App catalog default added to `modules/hosts/common/apps-enable.nix`, with host override entries only for real divergences
- [ ] `nix build .#nixosConfigurations.<host>.pkgs.<name>` succeeds for overlay-backed packages
- [ ] `./packages/<name>/update.py --force` succeeds when an updater is present
- [ ] `script=$(nix eval --accept-flake-config --raw .#nixosConfigurations.system76.pkgs.<name>.passthru.updateScript); "$script" --force` succeeds when an updater is present
- [ ] `nix develop --no-write-lock-file -c hook-apps-catalog-sync` passes when app catalog files changed
- [ ] `nix flake check --accept-flake-config` passes for structural package/module changes

## Reference Implementations

| Package Type     | Reference                                  |
| ---------------- | ------------------------------------------ |
| Go               | `packages/age-plugin-fido2prf/default.nix` |
| Python           | `packages/wappalyzer-next/default.nix`     |
| Rust             | `packages/searchfox-cli/default.nix`       |
| Binary download  | `packages/charles/default.nix`             |
| Shell wrapper    | `packages/dnsleak/default.nix`             |
| Complex Java     | `packages/malimite/default.nix`            |
| Electron wrapper | `packages/raindrop/default.nix`            |
