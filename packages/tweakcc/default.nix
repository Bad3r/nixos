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
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "tweakcc";
  version = "unstable-2026-01-31";

  src = fetchFromGitHub {
    owner = "Piebald-AI";
    repo = "tweakcc";
    rev = "c497a00080194260b663ae13b6fd620c8fccd44e";
    hash = "sha256-v87JKPmhJ+RgZxPXo2oSpKz6e2yUgOTwj+yF4x0W3JM=";
  };

  nativeBuildInputs = [
    nodejs_22
    pnpm_9
    pnpmConfigHook
    makeWrapper
    autoPatchelfHook
  ];

  # libstdc++ for node-lief native addon
  buildInputs = [ stdenv.cc.cc.lib ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_9;
    fetcherVersion = 3;
    hash = "sha256-KEREgKLRxHIs1Kl5BRvzcvTNZosQDe/Z34MjW7yQegQ=";
  };

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';

  # Remove musl binaries before autoPatchelfHook (we use glibc)
  preFixup = ''
    find $out -name "*.musl.node" -delete
    find $out -path "*linux-x64-musl*" -delete
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/tweakcc $out/bin

    # Copy bundled output and package.json
    cp -r dist package.json $out/lib/tweakcc/

    # Reinstall with shamefully-hoist for full ESM compatibility
    rm -rf node_modules
    echo "node-linker=hoisted" > .npmrc
    echo "shamefully-hoist=true" >> .npmrc
    pnpm --offline --prod --ignore-scripts install

    # Copy flattened node_modules (dereference is safe with hoisted)
    cp -rL node_modules $out/lib/tweakcc/

    # Create wrapper with XDG-compliant config dir (--run for runtime expansion)
    makeWrapper ${nodejs_22}/bin/node $out/bin/tweakcc \
      --chdir "$out/lib/tweakcc" \
      --add-flags "$out/lib/tweakcc/dist/index.mjs" \
      --run 'export TWEAKCC_CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/tweakcc"'

    runHook postInstall
  '';

  meta = {
    description = "Customize Claude Code themes, thinking verbs, and system prompts";
    homepage = "https://github.com/Piebald-AI/tweakcc";
    license = lib.licenses.mit;
    mainProgram = "tweakcc";
    platforms = lib.platforms.linux;
  };
})
