{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
}:

buildNpmPackage rec {
  pname = "codeburn";
  version = "0.9.5";

  src = fetchFromGitHub {
    owner = "getagentseal";
    repo = "codeburn";
    rev = "v${version}";
    hash = "sha256-54NWcnVXQIDz2JzzFW8SJ+I2Ff6KyumrO3DdrvzuHUE=";
  };

  nodejs = nodejs_22;

  npmDepsHash = "sha256-vcChnFLiuiymqZb4ojvv7a7Cdg4BYYT+ZraTVELEsQ0=";

  # The upstream `build` script invokes scripts/bundle-litellm.mjs, which
  # downloads the LiteLLM price table from the network. The snapshot it would
  # produce is already committed to src/data/litellm-snapshot.json, so drop
  # the script and run tsup directly. Re-verify the substituted text on the
  # next version bump.
  postPatch = ''
    substituteInPlace package.json \
      --replace-fail '"build": "node scripts/bundle-litellm.mjs && tsup"' \
                     '"build": "tsup"'
    rm scripts/bundle-litellm.mjs
  '';

  meta = {
    description = "Interactive TUI dashboard for AI coding token cost observability";
    homepage = "https://github.com/getagentseal/codeburn";
    license = lib.licenses.mit;
    mainProgram = "codeburn";
    platforms = lib.platforms.linux;
  };
}
