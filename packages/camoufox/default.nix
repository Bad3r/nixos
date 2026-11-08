{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
  jq,
  makeWrapper,
  patchelfUnstable,
  python3Packages,
  alsa-lib,
  curl,
  dbus-glib,
  gtk3,
  libgbm,
  libglvnd,
  libva,
  libxtst,
  pciutils,
  pipewire,
  udev,
}:

let
  pin = lib.importJSON ./hashes.json;
  # dlopened at run time, as wrapFirefox provides them: GL for the software
  # renderer on Xvfb, VA-API, PCI and udev probing, PipeWire.
  runtimeLibraries = [
    curl
    libgbm
    libglvnd
    libva
    pciutils
    pipewire
    udev
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "camoufox";
  inherit (pin) version;

  src = fetchurl {
    url = "https://github.com/daijro/camoufox/releases/download/v${finalAttrs.version}/camoufox-${finalAttrs.version}-lin.x86_64.zip";
    hash = pin.srcHash;
  };

  sourceRoot = ".";
  unpackCmd = "unzip -q $curSrc -d camoufox";

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
    jq
    makeWrapper
    patchelfUnstable
  ];

  buildInputs = [
    alsa-lib
    dbus-glib
    gtk3
    libxtst
  ];

  # Firefox's relrhack processes relocations from a fixed offset.
  patchelfFlags = [ "--no-clobber-old-sections" ];

  dontConfigure = true;
  dontBuild = true;

  # A Linux fingerprint reads only the font groups groups.json lists for
  # "lin" (the launcher's _generate_fontconfig); the macOS- and
  # Windows-only groups are dropped, and the build fails if Linux reads one.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/bin
    jq -e '.readBy.lin - ["L", "LM", "LMW", "LW"] == []' camoufox/fonts/groups.json
    rm -r camoufox/fonts/{M,MW,W}
    cp -r camoufox $out/lib/camoufox
    ln -s $out/lib/camoufox/camoufox $out/bin/camoufox
    runHook postInstall
  '';

  # Beside the binary, so Firefox still finds its files next to it.
  postFixup = ''
    for exe in camoufox camoufox-bin; do
      wrapProgram $out/lib/camoufox/$exe \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibraries}
    done
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    grep -qx "Version=${finalAttrs.version}" $out/lib/camoufox/application.ini
    HOME=$TMPDIR $out/lib/camoufox/camoufox --version
    runHook postInstallCheck
  '';

  passthru = {
    # What Camoufox's launcher starts on Linux (pkgman.LAUNCH_FILE).
    executable = "${finalAttrs.finalPackage}/lib/camoufox/camoufox-bin";
    python = python3Packages.callPackage ./python.nix {
      inherit pin;
      camoufox = finalAttrs.finalPackage;
    };
    updateScript = ./update.py;
  };

  meta = {
    description = "Firefox build that spoofs a consistent device fingerprint, driven through Playwright";
    homepage = "https://camoufox.com/";
    changelog = "https://github.com/daijro/camoufox/releases/tag/v${finalAttrs.version}";
    # The browser is MPL-2.0 and the bundled uBlock Origin GPL-3.0-or-later.
    # The Linux font groups add their own licenses, and Adobe's Kozuka
    # Mincho and Gothic Pr6N and Myriad Pro, which are not free.
    license = with lib.licenses; [
      mpl20
      gpl3Plus
      unfree
      ofl
      asl20
      ufl
      gpl2Only
      agpl3Only
      bitstreamVera
      cc-by-40
      arphicpl
      mit
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "camoufox";
  };
})
