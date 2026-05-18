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
  pname = "source-map-explorer";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "danvk";
    repo = "source-map-explorer";
    rev = "v${version}";
    hash = pin.srcHash;
  };

  nodejs = nodejs_22;

  inherit (pin) npmDepsHash;

  passthru.updateScript = ./update.py;

  meta = {
    description = "Analyze and debug space usage through source maps";
    homepage = "https://github.com/danvk/source-map-explorer";
    license = lib.licenses.asl20;
    mainProgram = "source-map-explorer";
    platforms = lib.platforms.linux;
  };
}
