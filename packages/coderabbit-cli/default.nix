{
  lib,
  stdenvNoCC,
  fetchzip,
}:

let
  version = "0.3.2";

  downloads = {
    x86_64-linux = {
      url = "https://cli.coderabbit.ai/releases/${version}/coderabbit-linux-x64.zip";
      sha256 = "sha256-5OdV+uJb/CcEb96rE/FWH62X8+9j8ogpVaQyWZWUsek=";
    };

    aarch64-linux = {
      url = "https://cli.coderabbit.ai/releases/${version}/coderabbit-linux-arm64.zip";
      sha256 = "sha256-r3Nmt8F/sswZsunKtp2KXGPMRqaA7pdEPpzDcqRpx20=";
    };
  };

  platform =
    downloads.${stdenvNoCC.hostPlatform.system}
      or (throw "coderabbit-cli: unsupported system ${stdenvNoCC.hostPlatform.system}");

in
stdenvNoCC.mkDerivation {
  pname = "coderabbit-cli";
  inherit version;

  src = fetchzip {
    inherit (platform) url sha256;
    stripRoot = false;
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 "$src/coderabbit" "$out/bin/coderabbit"
    ln -s coderabbit "$out/bin/cr"

    runHook postInstall
  '';

  meta = {
    description = "CodeRabbit command-line interface";
    homepage = "https://coderabbit.ai";
    license = lib.licenses.unfreeRedistributable;
    mainProgram = "coderabbit";
    platforms = builtins.attrNames downloads;
  };
}
