# Custom Packages Style Guide

This guide defines the conventions for adding custom packages under `packages/<name>/default.nix`. Use it alongside the existing packages as references, and see `docs/apps-module-style-guide.md` for the corresponding app module pattern.

## When to Create a Custom Package

Create a custom package when:

- The software is not available in nixpkgs
- The nixpkgs version is outdated or broken and upstream hasn't merged a fix
- You need custom build flags, patches, or configuration not suitable for upstream

When a package becomes available in nixpkgs, deprecate the custom package by prefixing the file with `_` (e.g., `_default.nix`) and adding a deprecation comment.

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
└── codex/
    ├── _default.nix              # Deprecated (prefixed with _)
    └── disable-update-check.patch
```

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

rustPlatform.buildRustPackage rec {
  pname = "example-tool";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = "example-tool";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  cargoHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

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

  text = ''
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

## Registering in the Overlay

After creating the package, register it in `modules/system76/custom-packages-overlay.nix`:

```nix
_: {
  configurations.nixos.system76.module = {
    nixpkgs.overlays = [
      (final: _prev: {
        # Existing packages...
        my-new-package = final.callPackage ../../packages/my-new-package { };
      })
    ];
  };
}
```

This makes the package available as `pkgs.my-new-package` throughout the configuration.

## Hash Fetching Workflow

### Source Hash (fetchFromGitHub, fetchurl, fetchzip)

1. Set an invalid placeholder hash:

   ```nix
   hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
   ```

2. Attempt to build:

   ```bash
   nix build .#my-package
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

### Vendor Hash (Go packages)

Same workflow as cargoHash—use placeholder, build, copy the correct hash.

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

Skip the app module when:

- The package is host-specific tooling
- The package is only used in devshells
- The package is a library or build tool

See `docs/apps-module-style-guide.md` for the app module format.

## Deprecating a Package

When a package becomes available in nixpkgs:

1. Prefix the file with `_` to prevent auto-import:

   ```
   packages/codex/default.nix → packages/codex/_default.nix
   ```

2. Add a deprecation comment at the top:

   ```nix
   # DEPRECATED: This custom package is no longer used.
   # Codex is now installed from upstream nixpkgs.
   # This file is prefixed with '_' to prevent auto-import.
   # Kept for reference in case upstream regresses.
   ```

3. Comment out the overlay registration:
   ```nix
   # codex = final.callPackage ../../packages/codex { };  # DEPRECATED
   ```

## Validation Checklist

Before committing a new package:

- [ ] File exists at `packages/<name>/default.nix`
- [ ] All required meta fields are present
- [ ] Package is registered in `custom-packages-overlay.nix`
- [ ] `nix build .#<name>` succeeds (or via overlay: test in config)
- [ ] `nix flake check --accept-flake-config` passes
- [ ] App module created if user-facing (see `docs/apps-module-style-guide.md`)

## Reference Implementations

| Package Type     | Reference                                  |
| ---------------- | ------------------------------------------ |
| Go               | `packages/age-plugin-fido2prf/default.nix` |
| Python           | `packages/wappalyzer-next/default.nix`     |
| Binary download  | `packages/coderabbit-cli/default.nix`      |
| Shell wrapper    | `packages/dnsleak/default.nix`             |
| Complex Java     | `packages/malimite/default.nix`            |
| Electron wrapper | `packages/raindrop/default.nix`            |
