{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

let
  pin = lib.importJSON ./hashes.json;
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "wakaru";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "pionxzh";
    repo = "wakaru";
    rev = "v${finalAttrs.version}";
    hash = pin.srcHash;
  };

  inherit (pin) cargoHash;

  # crates/wasm is a wasm-only cdylib (wasm-bindgen, getrandom wasm_js) that
  # cannot build for the host target, so restrict the build to the CLI crate.
  cargoBuildFlags = [
    "--package"
    "wakaru-cli"
  ];

  # The test suite lives in the core/formatter crates and drives insta snapshot
  # fixtures (`.cargo/config.toml` sets INSTA_UPDATE=new, which fails on drift).
  # The CLI crate itself carries no unit tests, so checks add build cost without
  # exercising the packaged binary.
  doCheck = false;

  passthru.updateScript = ./update.py;

  meta = {
    description = "Fast JavaScript decompiler and bundle splitter";
    homepage = "https://github.com/pionxzh/wakaru";
    changelog = "https://github.com/pionxzh/wakaru/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "wakaru";
    platforms = lib.platforms.linux;
  };
})
