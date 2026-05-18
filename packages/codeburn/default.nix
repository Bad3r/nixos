{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
}:

let
  pin = lib.importJSON ./hashes.json;
in
buildNpmPackage rec {
  pname = "codeburn";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "getagentseal";
    repo = "codeburn";
    rev = "v${version}";
    hash = pin.srcHash;
  };

  nodejs = nodejs_22;

  inherit (pin) npmDepsHash;

  # The upstream `build` script invokes scripts/bundle-litellm.mjs, which
  # downloads the LiteLLM price table from the network. The snapshot it would
  # produce is already committed to src/data/litellm-snapshot.json, so drop
  # that network step and keep the rest of the build script intact.
  postPatch = ''
    substituteInPlace package.json \
      --replace-fail 'node scripts/bundle-litellm.mjs && ' \
                     ""
    rm scripts/bundle-litellm.mjs
  '';

  passthru.updateScript = ./update.py;

  meta = {
    description = "Interactive TUI dashboard for AI coding token cost observability";
    homepage = "https://github.com/getagentseal/codeburn";
    license = lib.licenses.mit;
    mainProgram = "codeburn";
    platforms = lib.platforms.linux;
  };
}
