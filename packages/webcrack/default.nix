{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  pnpm_9,
  fetchPnpmDeps,
  pnpmConfigHook,
  makeWrapper,
  autoPatchelfHook,
  jq,
  yq-go,
  python3,
}:

let
  version = "2.15.1";

  # Patch source to remove patchedDependencies which causes lockfile mismatch
  patchedSrc = stdenv.mkDerivation {
    name = "webcrack-source-patched";

    src = fetchFromGitHub {
      owner = "j4k0xb";
      repo = "webcrack";
      rev = "v${version}";
      hash = "sha256-9xCndYtGXnVGV6gXdqjLM4ruSIHi7JRXPHRBom7K7Ds=";
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

      # Upgrade isolated-vm 5.0.1 -> 6.0.2 (5.0.1 fails to compile with current GCC)
      # Update packages/webcrack/package.json dependency
      ${lib.getExe jq} '.dependencies["isolated-vm"] = "^6.0.2"' \
        $out/packages/webcrack/package.json > $out/packages/webcrack/package.json.tmp
      mv $out/packages/webcrack/package.json.tmp $out/packages/webcrack/package.json

      # Update pnpm-lock.yaml for isolated-vm 5.0.1 -> 6.0.2
      ${lib.getExe yq-go} -i '
        .importers."packages/webcrack".dependencies."isolated-vm".specifier = "^6.0.2" |
        .importers."packages/webcrack".dependencies."isolated-vm".version = "6.0.2" |
        .packages."isolated-vm@6.0.2".resolution.integrity = "sha512-Qw6AJuagG/VJuh2AIcSWmQPsAArti/L+lKhjXU+lyhYkbt3J57XZr+ZjgfTnOr4NJcY1r3f8f0eePS7MRGp+pg==" |
        .packages."isolated-vm@6.0.2".engines.node = ">=22.0.0" |
        .snapshots."isolated-vm@6.0.2".dependencies."prebuild-install" = "7.1.2"
      ' $out/pnpm-lock.yaml
    '';
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "webcrack";
  inherit version;
  src = patchedSrc;

  nativeBuildInputs = [
    nodejs_22
    pnpm_9
    pnpmConfigHook
    makeWrapper
    autoPatchelfHook
    python3 # for node-gyp (isolated-vm)
  ];

  # Libraries for native addons (isolated-vm links against Node internals)
  buildInputs = [
    stdenv.cc.cc.lib
    nodejs_22 # provides libuv, openssl, icu, etc.
  ];

  # Point node-gyp to Node headers (prevents download in sandbox)
  env.npm_config_nodedir = nodejs_22;

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_9;
    fetcherVersion = 3;
    hash = "sha256-WuLdIcbN9MI3baerKZtHcY5KbG/AFImhafufiX8mHHI=";
  };

  buildPhase = ''
    runHook preBuild

    # Build isolated-vm native module (pnpmConfigHook skips install scripts)
    cd node_modules/.pnpm/isolated-vm@6.0.2/node_modules/isolated-vm
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

  # isolated-vm links against Node.js internal libraries (libuv, openssl, icu, sqlite, etc.)
  # These are provided by Node.js at runtime, so we can safely ignore them
  autoPatchelfIgnoreMissingDeps = [
    "libuv.so.1"
    "libssl.so.3"
    "libcrypto.so.3"
    "libicuuc.so.76"
    "libicui18n.so.76"
    "libsqlite3.so"
    "libuvwasi.so"
    "libz.so.1"
    "libnghttp2.so.14"
    "libnghttp3.so.9"
    "libngtcp2.so.16"
    "libngtcp2.so.17"
    "libngtcp2_crypto_quictls.so.8"
    "libcares.so.2"
    "libbrotlidec.so.1"
    "libbrotlienc.so.1"
    "libsimdjson.so.22"
    "libsimdjson.so.29"
    "libllhttp.so.9.3"
    "libada.so.3"
    "libnbytes.so.0"
    "libncrypto.so.0"
  ];

  # NOTE: Copies pnpm workspace to preserve symlink structure for runtime.
  # Uses isolated-vm 6.0.2 (patched from 5.0.1) for VM-based deobfuscation.
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

  meta = {
    description = "Deobfuscate obfuscator.io, unminify and unpack bundled javascript";
    homepage = "https://github.com/j4k0xb/webcrack";
    license = lib.licenses.mit;
    mainProgram = "webcrack";
    platforms = lib.platforms.linux;
  };
})
