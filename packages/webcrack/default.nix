# NOTE: webcrack only supports webpack and browserify bundles.
# It does NOT support esbuild/bun ESM bundles (misdetects as browserify).
# See LIMITATIONS.md for details on bundle format detection.
{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  makeWrapper,
  autoPatchelfHook,
  jq,
  yq-go,
  python3,
  ada,
  brotli,
  c-ares,
  icu76,
  libuv,
  llhttp,
  nghttp2,
  nghttp3,
  ngtcp2,
  openssl,
  simdjson,
  simdutf,
  sqlite,
  uvwasi,
  zlib,
}:

let
  pin = lib.importJSON ./hashes.json;
  simdutf_6 = simdutf.overrideAttrs {
    version = pin.simdutfVersion;
    src = fetchFromGitHub {
      owner = "simdutf";
      repo = "simdutf";
      rev = "v${pin.simdutfVersion}";
      hash = pin.simdutfHash;
    };
  };

  # Patch source to remove patchedDependencies which causes lockfile mismatch
  patchedSrc = stdenv.mkDerivation {
    name = "webcrack-source-patched";

    src = fetchFromGitHub {
      owner = "j4k0xb";
      repo = "webcrack";
      rev = "v${pin.version}";
      hash = pin.srcHash;
    };

    nativeBuildInputs = [
      jq
      yq-go
    ];
    dontBuild = true;

    installPhase = ''
      cp -r . $out

      # Remove patchedDependencies from package.json and pnpm-lock.yaml
      ${lib.getExe jq} 'del(.pnpm.patchedDependencies)' $out/package.json > $out/package.json.tmp
      mv $out/package.json.tmp $out/package.json
      ${lib.getExe yq-go} -i 'del(.patchedDependencies)' $out/pnpm-lock.yaml

      # Keep isolated-vm pinned to the updater-owned lock metadata.
      ${lib.getExe jq} '.dependencies["isolated-vm"] = "^${pin.isolatedVmVersion}"' \
        $out/packages/webcrack/package.json > $out/packages/webcrack/package.json.tmp
      mv $out/packages/webcrack/package.json.tmp $out/packages/webcrack/package.json

      ${lib.getExe yq-go} -i '
        .importers."packages/webcrack".dependencies."isolated-vm".specifier = "^${pin.isolatedVmVersion}" |
        .importers."packages/webcrack".dependencies."isolated-vm".version = "${pin.isolatedVmVersion}" |
        .packages."isolated-vm@${pin.isolatedVmVersion}".resolution.integrity = "${pin.isolatedVmIntegrity}" |
        .packages."isolated-vm@${pin.isolatedVmVersion}".engines.node = ">=22.0.0"
      ' $out/pnpm-lock.yaml
    '';
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "webcrack";
  inherit (pin) version;
  src = patchedSrc;

  nativeBuildInputs = [
    nodejs_22
    pnpm_10
    pnpmConfigHook
    makeWrapper
    autoPatchelfHook
    python3 # for node-gyp (isolated-vm)
  ];

  # Libraries for native addons (isolated-vm links against Node internals)
  buildInputs = [
    stdenv.cc.cc.lib
    nodejs_22
    (lib.getLib zlib)
    (lib.getLib llhttp)
    (lib.getLib libuv)
    (lib.getLib ada)
    (lib.getLib simdjson)
    (lib.getLib simdutf_6)
    (lib.getLib brotli)
    (lib.getLib c-ares)
    (lib.getLib nghttp2)
    (lib.getLib nghttp3)
    (lib.getLib ngtcp2)
    (lib.getLib sqlite)
    (lib.getLib uvwasi)
    (lib.getLib openssl)
    (lib.getLib icu76)
  ];

  # Point node-gyp to Node headers (prevents download in sandbox)
  env.npm_config_nodedir = nodejs_22;

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 3;
    hash = pin.pnpmDepsHash;
  };

  buildPhase = ''
    runHook preBuild

    # Build isolated-vm native module (pnpmConfigHook skips install scripts)
    cd node_modules/.pnpm/isolated-vm@${pin.isolatedVmVersion}/node_modules/isolated-vm
    npm run rebuild
    cd -

    pnpm --filter=webcrack build
    runHook postBuild
  '';

  # Remove musl binaries before autoPatchelfHook (we use glibc)
  preFixup = ''
    find $out -name "*.musl.node" -delete
    find $out -path "*linux-x64-musl*" -delete
  '';

  # NOTE: Copies pnpm workspace to preserve symlink structure for runtime.
  # Uses the updater-pinned isolated-vm for VM-based deobfuscation.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/webcrack $out/bin

    # Copy entire workspace (preserves pnpm symlink structure)
    cp -r . $out/lib/webcrack/

    # Remove source files and tests (keep dist, node_modules, package files)
    rm -rf $out/lib/webcrack/packages/*/src
    rm -rf $out/lib/webcrack/packages/*/test
    rm -rf $out/lib/webcrack/.git
    find $out/lib/webcrack -name "*.ts" -not -name "*.d.ts" -delete 2>/dev/null || true
    find $out/lib/webcrack -name "*.md" -delete 2>/dev/null || true
    find $out/lib/webcrack -maxdepth 2 -name "*.config.*" -delete 2>/dev/null || true
    find $out/lib/webcrack -maxdepth 2 -name "tsconfig*.json" -delete 2>/dev/null || true

    # Remove only dangling symlinks pointing to apps/ (web, playground, docs)
    # Keep other symlinks intact for isolated-vm and runtime deps
    find $out/lib/webcrack/node_modules -xtype l -lname "*apps/*" -delete 2>/dev/null || true

    makeWrapper ${nodejs_22}/bin/node $out/bin/webcrack \
      --chdir "$out/lib/webcrack" \
      --add-flags "$out/lib/webcrack/packages/webcrack/dist/cli.js"

    runHook postInstall
  '';

  passthru.updateScript = ./update.py;

  meta = {
    description = "Deobfuscate obfuscator.io, unminify and unpack bundled javascript";
    homepage = "https://github.com/j4k0xb/webcrack";
    license = lib.licenses.mit;
    mainProgram = "webcrack";
    platforms = lib.platforms.linux;
  };
})
