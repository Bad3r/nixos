# Packaging JavaScript/Node.js Applications

This guide covers packaging npm, pnpm, and bun-based JavaScript applications in NixOS.

## Reference Implementations

These nixpkgs packages demonstrate various patterns for packaging JavaScript applications:

| Package              | Path                                                             | Pattern                                       | When to Use                                                     |
| -------------------- | ---------------------------------------------------------------- | --------------------------------------------- | --------------------------------------------------------------- |
| **Misskey**          | `$HOME/git/nixpkgs/pkgs/by-name/mi/misskey/package.nix`          | Copy entire workspace, wrap `pnpm run`        | pnpm monorepos with native modules; preserves symlink structure |
| **cspell**           | `$HOME/git/nixpkgs/pkgs/by-name/cs/cspell/package.nix`           | `pnpmWorkspaces` filter + hoisted reinstall   | Monorepos without native modules; minimal closure               |
| **synchrony**        | `$HOME/git/nixpkgs/pkgs/by-name/sy/synchrony/package.nix`        | Simple `cp -r node_modules`                   | Single-package pnpm projects (non-monorepo)                     |
| **siyuan**           | `$HOME/git/nixpkgs/pkgs/by-name/si/siyuan/package.nix`           | `sourceRoot` + `postPatch` to `fetchPnpmDeps` | Monorepo subpackage with lockfile at root                       |
| **heroic-unwrapped** | `$HOME/git/nixpkgs/pkgs/by-name/he/heroic-unwrapped/package.nix` | `npm_config_nodedir` for native modules       | Electron/native addons needing Node headers                     |
| **tweakcc**          | `packages/tweakcc/default.nix` (local)                           | shamefully-hoist + autoPatchelfHook           | ESM apps with prebuilt native addons, external deps             |

> **Note:** nixpkgs paths reference a local clone at `$HOME/git/nixpkgs`. Clone via `ghq get NixOS/nixpkgs` or adjust paths.

## pnpm Packages

### pnpm Version Selection

Use pinned versions (`pnpm_8`, `pnpm_9`, `pnpm_10`) matching the lockfile version:

- Check `lockfileVersion` in `pnpm-lock.yaml`
- Pass the same version to both `nativeBuildInputs` and `fetchPnpmDeps`

### Basic Structure

```nix
{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs,
  pnpm_9,
  fetchPnpmDeps,
  pnpmConfigHook,
  makeWrapper,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "my-package";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = "my-package";
    rev = "v${finalAttrs.version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm_9
    pnpmConfigHook
    makeWrapper
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_9;
    fetcherVersion = 3;  # Use latest; see fetcherVersion section below
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/my-package $out/bin
    cp -r dist node_modules package.json $out/lib/my-package/
    makeWrapper ${nodejs}/bin/node $out/bin/my-package \
      --add-flags "$out/lib/my-package/dist/cli.js"
    runHook postInstall
  '';

  meta = {
    description = "My package description";
    homepage = "https://example.com";
    license = lib.licenses.mit;
    mainProgram = "my-package";
  };
})
```

### Getting Hashes

Build with placeholder hashes and Nix will report the correct ones:

```bash
nix-build --expr 'let pkgs = import <nixpkgs> {}; in pkgs.callPackage ./packages/my-package {}'
```

### fetcherVersion

Controls output format of `fetchPnpmDeps`. Use `3` for new packages:

- **1**: Legacy format (backwards compatibility only)
- **2**: Consistent file permissions ([PR #422975](https://github.com/NixOS/nixpkgs/pull/422975))
- **3**: Reproducible tarball, smaller closure ([PR #469950](https://github.com/NixOS/nixpkgs/pull/469950))

Changing version requires regenerating the hash.

## pnpm Monorepo Patterns

### Pattern 1: Copy Entire Workspace (Misskey Pattern)

Best for monorepos with native modules that need network access during rebuild.

```nix
installPhase = ''
  mkdir -p $out/lib/my-app $out/bin
  cp -r . $out/lib/my-app/
  makeWrapper ${nodejs}/bin/node $out/bin/my-app \
    --chdir "$out/lib/my-app" \
    --add-flags "$out/lib/my-app/packages/cli/dist/index.js"
'';
```

**Trade-off:** Larger closure (includes dev dependencies) but preserves pnpm symlink structure.

### Pattern 2: Hoisted Reinstall (cspell Pattern)

Best for monorepos without native modules. Produces minimal closure.

```nix
pnpmWorkspaces = [ "my-package..." ];

pnpmDeps = fetchPnpmDeps {
  inherit (finalAttrs) pname version src pnpmWorkspaces;
  # ...
};

installPhase = ''
  rm -rf node_modules packages/*/node_modules
  pnpm config set nodeLinker hoisted
  pnpm config set preferSymlinkedExecutables false
  pnpm --filter="my-package" --offline --prod install

  mkdir -p $out/lib/node_modules/my-package $out/bin
  cp -r packages/my-package/dist $out/lib/node_modules/my-package/
  cp packages/my-package/package.json $out/lib/node_modules/my-package/
  cp -rL packages/my-package/node_modules $out/lib/node_modules/my-package/
'';
```

**Limitation:** Fails if native modules need to rebuild (can't fetch Node headers in sandbox).

### Pattern 3: sourceRoot for Subpackages (siyuan Pattern)

When lockfile is at repo root but you only need one subpackage:

```nix
sourceRoot = "${finalAttrs.src.name}/packages/my-package";

postPatch = ''
  rm -f pnpm-workspace.yaml
'';

pnpmDeps = fetchPnpmDeps {
  inherit (finalAttrs) pname version src sourceRoot;
  postPatch = finalAttrs.postPatch;
  # ...
};
```

## Handling Native Modules

### Node Headers for node-gyp

Prevent node-gyp from downloading headers:

- **Pure Node.js apps**: Point to Node headers

  ```nix
  env.npm_config_nodedir = nodejs;
  ```

- **Electron apps**: Point to Electron headers (ABI differs from Node)
  ```nix
  export npm_config_nodedir=${electron.headers}
  ```

### Python for node-gyp

Many native modules require Python:

```nix
nativeBuildInputs = [
  nodejs
  pnpm_9
  pnpmConfigHook
  python3  # for node-gyp
];
```

### Prebuilt Native Addons

Some packages ship prebuilt `.node` binaries instead of building from source. Use `autoPatchelfHook` to fix library paths:

```nix
nativeBuildInputs = [
  nodejs
  pnpm_9
  pnpmConfigHook
  makeWrapper
  autoPatchelfHook
];

# libstdc++ for native addons
buildInputs = [ stdenv.cc.cc.lib ];

# Remove musl binaries (we use glibc)
preFixup = ''
  find $out -name "*.musl.node" -delete
  find $out -path "*linux-x64-musl*" -delete
'';
```

The `preFixup` runs before `autoPatchelfHook`, removing incompatible musl variants that would cause patching errors.

## Electron Apps

Electron packaging requires additional configuration:

### Skip Binary Downloads

Prevent Electron from downloading binaries during build:

```nix
env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
```

### Native Modules with electron-builder

Use `electron.headers`, `electron.dist`, and `electron.version`:

```nix
buildPhase = ''
  runHook preBuild
  export npm_config_nodedir=${electron.headers}
  pnpm build
  npm exec electron-builder -- \
    --dir \
    -c.electronDist=${electron.dist} \
    -c.electronVersion=${electron.version}
  runHook postBuild
'';
```

### Wrapper Pattern

Wrap the Electron binary, not Node:

```nix
makeWrapper ${lib.getExe electron} $out/bin/my-app \
  --add-flags $out/share/my-app/resources/app.asar \
  --set ELECTRON_FORCE_IS_PACKAGED 1
```

See `heroic-unwrapped` and `siyuan` for complete examples.

### Preserving Pre-built Native Modules

If native modules are built during build phase but you need to reinstall during install:

```nix
installPhase = ''
  # Save pre-built native module
  cp -r node_modules/.pnpm/native-pkg@*/node_modules/native-pkg/build /tmp/native-build

  # Reinstall with --ignore-scripts
  rm -rf node_modules
  pnpm --offline --prod --ignore-scripts install

  # Restore pre-built native module
  cp -r /tmp/native-build node_modules/native-pkg/
'';
```

## Common Issues and Solutions

### patchedDependencies Lockfile Mismatch

If the project uses `pnpm.patchedDependencies` in package.json:

```nix
let
  patchedSrc = stdenv.mkDerivation {
    name = "source-patched";
    inherit src;
    nativeBuildInputs = [ jq yq-go ];
    dontBuild = true;
    installPhase = ''
      cp -r . $out
      ${lib.getExe jq} 'del(.pnpm.patchedDependencies)' $out/package.json > $out/package.json.tmp
      mv $out/package.json.tmp $out/package.json
      ${lib.getExe yq-go} -i 'del(.patchedDependencies)' $out/pnpm-lock.yaml
    '';
  };
in
stdenv.mkDerivation {
  src = patchedSrc;
  # ...
}
```

### Broken Symlinks After Copy

pnpm uses symlinks to `.pnpm` store. When copying, either:

1. Dereference symlinks: `cp -rL node_modules $out/`
2. Copy entire workspace to preserve structure

### ESM Module Resolution

ESM ignores `NODE_PATH`. Modules must be in proper node_modules hierarchy. Use `--chdir` in wrapper if needed:

```nix
makeWrapper ${nodejs}/bin/node $out/bin/my-app \
  --chdir "$out/lib/my-app" \
  --add-flags "$out/lib/my-app/dist/cli.js"
```

### Missing Transitive Dependencies (ESM + pnpm)

pnpm's nested `node_modules` breaks ESM resolution for transitive deps. Use `shamefully-hoist` via `.npmrc` (not `pnpm config set`):

```nix
installPhase = ''
  rm -rf node_modules
  echo "node-linker=hoisted" > .npmrc
  echo "shamefully-hoist=true" >> .npmrc
  pnpm --offline --prod --ignore-scripts install
  cp -rL node_modules $out/lib/my-app/
'';
```

This flattens all deps to node_modules root, enabling proper ESM resolution.

### Bundlers That Don't Bundle Dependencies

Tools like tsdown/tsup mark `dependencies` as external by default. Check for `rollup-plugin-node-externals` in `devDependencies`. If present, the build output requires `node_modules` at runtime:

```nix
# Copy both bundled output AND node_modules
cp -r dist package.json $out/lib/my-app/
cp -rL node_modules $out/lib/my-app/
```

## Searching for Examples

Find pnpm packages in nixpkgs:

```bash
rg -l 'pnpmConfigHook' $HOME/git/nixpkgs/pkgs/by-name
```

Find packages with specific patterns:

```bash
# Monorepo with workspaces
rg 'pnpmWorkspaces' $HOME/git/nixpkgs/pkgs/by-name

# Native module handling
rg 'npm_config_nodedir' $HOME/git/nixpkgs/pkgs/by-name

# Hoisted node_modules
rg 'nodeLinker hoisted' $HOME/git/nixpkgs/pkgs/by-name
```

## npm Packages

For npm-based packages, use `buildNpmPackage`:

```nix
{ buildNpmPackage, fetchFromGitHub }:

buildNpmPackage {
  pname = "my-npm-package";
  version = "1.0.0";

  src = fetchFromGitHub { /* ... */ };

  npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  # Optional: for native modules
  makeCacheWritable = true;
}
```

## Bun Packages

For bun-based packages (experimental support in nixpkgs):

```nix
{ stdenv, bun, fetchFromGitHub }:

stdenv.mkDerivation {
  pname = "my-bun-package";
  version = "1.0.0";

  src = fetchFromGitHub { /* ... */ };

  nativeBuildInputs = [ bun ];

  buildPhase = ''
    bun install --frozen-lockfile
    bun run build
  '';

  # Note: Bun packaging in Nix is less mature than npm/pnpm
}
```

## Quick Reference

- **Get pnpm deps hash**: Build with placeholder, check error
- **Filter workspaces**: `pnpmWorkspaces = [ "pkg-name..." ];`
- **Flatten node_modules**: Write `.npmrc` with `node-linker=hoisted` and `shamefully-hoist=true`
- **Skip native rebuild**: `pnpm --ignore-scripts install`
- **Node headers (Node apps)**: `env.npm_config_nodedir = nodejs;`
- **Node headers (Electron)**: `export npm_config_nodedir=${electron.headers}`
- **Skip Electron download**: `env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";`
- **Prebuilt native addons**: `autoPatchelfHook` + `buildInputs = [ stdenv.cc.cc.lib ]`
- **Remove musl binaries**: `preFixup = ''find $out -name "*.musl.node" -delete'';`
- **Dereference symlinks**: `cp -rL node_modules $out/`
- **Production only**: `pnpm --prod install`
- **Offline install**: `pnpm --offline install`
