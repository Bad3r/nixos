{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go,
}:

let
  pin = lib.importJSON ./hashes.json;
in
buildGoModule rec {
  pname = "redress";
  inherit (pin) version vendorHash;

  src = fetchFromGitHub {
    owner = "goretk";
    repo = "redress";
    tag = "v${version}";
    hash = pin.srcHash;
  };

  ldflags = [
    "-s"
    "-w"
    "-X main.redressVersion=v${version}"
    "-X main.goreVersion=${pin.goreVersion}"
    "-X main.compilerVersion=go${go.version}"
  ];

  meta = {
    description = "Tool for analyzing stripped Go binaries";
    homepage = "https://github.com/goretk/redress";
    changelog = "https://github.com/goretk/redress/releases/tag/v${version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "redress";
    platforms = lib.platforms.unix;
  };

  passthru.updateScript = ./update.py;
}
