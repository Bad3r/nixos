{
  lib,
  buildGoModule,
  fetchFromGitHub,
  pkg-config,
  libfido2,
}:

buildGoModule {
  pname = "age-plugin-fido2prf";
  version = "0.2.4";

  src = fetchFromGitHub {
    owner = "FiloSottile";
    repo = "typage";
    rev = "v0.2.4";
    hash = "sha256-VKvIPgcZvfnf7ZU4ZkknvL4Ynxu3dE2R+aWrJLY2GeA=";
  };

  subPackages = [ "fido2prf/cmd/age-plugin-fido2prf" ];

  vendorHash = "sha256-XrgZBvNyVUhKJ87vfd9aZh6aW+JifJWUu/ggNQZKwo0=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libfido2 ];

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "FIDO2 WebAuthn-backed identity plugin for age";
    homepage = "https://github.com/FiloSottile/typage";
    changelog = "https://github.com/FiloSottile/typage/releases/tag/v0.2.4";
    license = lib.licenses.bsd3;
    mainProgram = "age-plugin-fido2prf";
    platforms = lib.platforms.unix;
  };
}
