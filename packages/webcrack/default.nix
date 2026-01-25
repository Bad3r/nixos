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
  ];

  # libstdc++ for rollup native addon
  buildInputs = [ stdenv.cc.cc.lib ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_9;
    fetcherVersion = 3;
    hash = "sha256-YGReNSMFWQXb/xHJPVuSczu37gNRq/o2nVsqNTJnF7U=";
  };

  buildPhase = ''
    runHook preBuild
    pnpm --filter=webcrack build
    runHook postBuild
  '';

  # Remove musl binaries before autoPatchelfHook (we use glibc)
  preFixup = ''
    find $out -name "*.musl.node" -delete
    find $out -path "*linux-x64-musl*" -delete
  '';

  # NOTE: Copies pnpm workspace to preserve symlink structure for runtime.
  # VM-based deobfuscation (isolated-vm) unavailable: isolated-vm 5.0.1
  # doesn't compile with Node.js 22, and prebuild-install can't download
  # prebuilts in sandbox. Basic deobfuscation works without it.
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
