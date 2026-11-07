{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
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

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/bin
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
    license = lib.licenses.mpl20;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "camoufox";
  };
})
