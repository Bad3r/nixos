{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  pnpm_9,
  fetchPnpmDeps,
  pnpmConfigHook,
  makeWrapper,
}:

let
  version = "0.0.10";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "wakaru";
  inherit version;

  src = fetchFromGitHub {
    owner = "pionxzh";
    repo = "wakaru";
    rev = "cli-v${version}";
    hash = "sha256-bWApVN11HZy88xHbB2fQdk4quiyKsn6oyHa91Unxjds=";
  };

  nativeBuildInputs = [
    nodejs_22
    pnpm_9
    pnpmConfigHook
    makeWrapper
  ];

  # Filter to CLI package and dependencies only, excluding playground/ide with missing npm packages
  pnpmWorkspaces = [ "@wakaru/cli..." ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs)
      pname
      version
      src
      pnpmWorkspaces
      ;
    pnpm = pnpm_9;
    fetcherVersion = 2;
    hash = "sha256-+A8NL6+FyJ1Cjgc+8JiFwdYKCnmICzbtMD5mKgWPw28=";
  };

  buildPhase = ''
    runHook preBuild

    pnpm --filter "@wakaru/cli..." build

    runHook postBuild
  '';

  # NOTE: Copies entire pnpm workspace to preserve symlink structure for runtime.
  # This includes dev dependencies which bloats the closure. The alternative
  # (hoisted reinstall) fails because transitive dependencies are missing.
  # Trade-off: larger size but correct behavior.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/wakaru $out/bin

    cp -r . $out/lib/wakaru/

    makeWrapper ${nodejs_22}/bin/node $out/bin/wakaru \
      --add-flags "--max-old-space-size=8192" \
      --add-flags "$out/lib/wakaru/packages/cli/dist/cli.cjs"

    runHook postInstall
  '';

  meta = {
    description = "Javascript decompiler for modern frontend";
    homepage = "https://github.com/pionxzh/wakaru";
    license = lib.licenses.mit;
    mainProgram = "wakaru";
    platforms = lib.platforms.linux;
  };
})
