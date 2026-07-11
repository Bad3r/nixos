{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.27.1";

  downloads = {
    x86_64-linux = {
      url = "https://github.com/Azure/azure-dev/releases/download/azure-dev-cli_${version}/azd-linux-amd64.tar.gz";
      hash = "sha256-EE2hHuS7ofCYlOur2Gc5qIcWL1NsHEDU3r4xzmo31T8=";
      binary = "azd-linux-amd64";
    };

    aarch64-linux = {
      url = "https://github.com/Azure/azure-dev/releases/download/azure-dev-cli_${version}/azd-linux-arm64.tar.gz";
      hash = "sha256-Eu77tYqv/9ZzzRlg6mrXH+L+F8aXa8pk20cv5oB/sho=";
      binary = "azd-linux-arm64";
    };
  };

  platform =
    downloads.${stdenvNoCC.hostPlatform.system}
      or (throw "azd: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "azd";
  inherit version;

  src = fetchurl {
    inherit (platform) url hash;
  };

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$TMPDIR/azd"
    tar -xzf "$src" -C "$TMPDIR/azd"

    install -Dm755 "$TMPDIR/azd/${platform.binary}" "$out/bin/azd"
    install -Dm644 "$TMPDIR/azd/NOTICE.txt" "$out/share/doc/azd/NOTICE.txt"

    runHook postInstall
  '';

  meta = {
    description = "Developer CLI for building and deploying applications on Azure";
    homepage = "https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/";
    changelog = "https://github.com/Azure/azure-dev/releases/tag/azure-dev-cli_${version}";
    license = lib.licenses.mit;
    mainProgram = "azd";
    platforms = builtins.attrNames downloads;
  };

  passthru.updateScript = ./update.py;
}
