{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

let
  pin = lib.importJSON ./hashes.json;
in
rustPlatform.buildRustPackage rec {
  pname = "wakaru";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "pionxzh";
    repo = "wakaru";
    rev = "v${version}";
    hash = pin.srcHash;
  };

  inherit (pin) cargoHash;

  cargoBuildFlags = [
    "-p"
    "wakaru-cli"
  ];
  cargoTestFlags = [
    "-p"
    "wakaru-cli"
  ];

  passthru.updateScript = ./update.py;

  meta = {
    description = "Fast JavaScript decompiler and bundle splitter";
    homepage = "https://github.com/pionxzh/wakaru";
    changelog = "https://github.com/pionxzh/wakaru/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "wakaru";
    platforms = lib.platforms.linux;
  };
}
