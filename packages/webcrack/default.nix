{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  pnpm_9,
  fetchPnpmDeps,
  pnpmConfigHook,
  makeWrapper,
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
    python3
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_9;
    fetcherVersion = 2;
    hash = "sha256-YGReNSMFWQXb/xHJPVuSczu37gNRq/o2nVsqNTJnF7U=";
  };

  buildPhase = ''
    runHook preBuild

    pnpm --filter=webcrack build

    runHook postBuild
  '';

  # NOTE: Copies entire pnpm workspace to preserve symlink structure for runtime.
  # This includes dev dependencies which bloats the closure. The alternative
  # (hoisted reinstall) fails because isolated-vm native module rebuild can't
  # fetch Node headers in sandbox. Trade-off: larger size but correct behavior.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/webcrack $out/bin

    cp -r . $out/lib/webcrack/

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
