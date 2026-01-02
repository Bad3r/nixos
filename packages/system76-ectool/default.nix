{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  hidapi,
}:

rustPlatform.buildRustPackage rec {
  pname = "system76-ectool";
  version = "0.3.8";

  src = fetchFromGitHub {
    owner = "system76";
    repo = "ec";
    rev = "a0b5f938bcf448b148dc5f09d93c55caf2e97a48";
    hash = "sha256-BgocSxVXOJRp3j8dTtkpiKlcfPKrLUi1VkTzqSgmEwE=";
  };

  sourceRoot = "${src.name}/tools/system76_ectool";

  cargoHash = "sha256-X19j9XG/lLAC9jE6/o7xF2forXpZuxvD8d+CxVqLrVA=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ hidapi ];
  buildFeatures = [
    "std"
    "hidapi"
    "clap"
  ];

  meta = {
    description = "System76 EC tool for fan control and firmware operations";
    homepage = "https://github.com/system76/ec";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "system76_ectool";
  };
}
