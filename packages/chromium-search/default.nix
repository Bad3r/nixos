{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python3,
}:

let
  pin = lib.importJSON ./hashes.json;
in
stdenvNoCC.mkDerivation {
  pname = "chromium-search";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "jclay";
    repo = "chromium-search";
    inherit (pin) rev;
    hash = pin.srcHash;
  };

  buildInputs = [ python3 ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 chromium-search.py $out/bin/chromium-search
    runHook postInstall
  '';

  # The syntax reference is printed locally; search, find, and cat need the network.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/chromium-search syntax | grep -q "Query Syntax Reference"
    runHook postInstallCheck
  '';

  passthru.updateScript = ./update.py;

  meta = {
    description = "CLI for Chromium Code Search (source.chromium.org)";
    homepage = "https://github.com/jclay/chromium-search";
    license = lib.licenses.mit;
    mainProgram = "chromium-search";
    platforms = lib.platforms.unix;
  };
}
