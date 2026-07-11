{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

# Wordlists shipped in the xmendez/wfuzz source tree, installed on their own so
# `pkgs.wordlists` (and csec.wordlists) no longer realize the full wfuzz Python
# application closure (pycurl, pyparsing, Python 3.13 compat patches) just to
# expose share/wordlists/wfuzz. Keep the src pin aligned with packages/wfuzz so
# the fetchFromGitHub output is shared instead of downloaded twice.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "wfuzz-wordlists";
  version = "3.1.1";

  src = fetchFromGitHub {
    owner = "xmendez";
    repo = "wfuzz";
    tag = "v${finalAttrs.version}";
    hash = "sha256-OYMZHo0ujRzwOcE+EKRNPxffxVbbiMHe+AqBz7q/u2A=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/wordlists"
    cp -R -T wordlist "$out/share/wordlists/wfuzz"
    runHook postInstall
  '';

  meta = {
    description = "Wordlists bundled with wfuzz, packaged without the wfuzz application";
    homepage = "https://github.com/xmendez/wfuzz";
    license = with lib.licenses; [ gpl2Only ];
    maintainers = with lib.maintainers; [ pamplemousse ];
    platforms = lib.platforms.all;
  };
})
