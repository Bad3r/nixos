{
  lib,
  buildGoModule,
  fetchFromGitHub,
  pkg-config,
  libfido2,
}:

let
  pin = lib.importJSON ./hashes.json;
in
buildGoModule rec {
  pname = "age-plugin-fido2prf";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "FiloSottile";
    repo = "typage";
    rev = "v${version}";
    hash = pin.srcHash;
  };

  subPackages = [ "fido2prf/cmd/age-plugin-fido2prf" ];

  inherit (pin) vendorHash;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libfido2 ];

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "FIDO2 WebAuthn-backed identity plugin for age";
    homepage = "https://github.com/FiloSottile/typage";
    changelog = "https://github.com/FiloSottile/typage/releases/tag/v${version}";
    license = lib.licenses.bsd3;
    mainProgram = "age-plugin-fido2prf";
    platforms = lib.platforms.unix;
  };

  passthru.updateScript = ./update.py;
}
