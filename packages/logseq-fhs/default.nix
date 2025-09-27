{
  lib,
  stdenv,
  fetchzip,
  buildFHSEnv,
  writeShellScriptBin,
  makeDesktopItem,
  copyDesktopItems,
  # runtime libs
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  dejavu_fonts,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gtk3,
  harfbuzz,
  krb5,
  libappindicator-gtk3,
  libdrm,
  libnotify,
  libpulseaudio,
  libsecret,
  libuuid,
  libxkbcommon,
  nspr,
  nss,
  pango,
  pipewire,
  udev,
  xdg-desktop-portal,
  xdg-user-dirs,
  xdg-utils,
  zlib,
  libX11,
  libXScrnSaver,
  libXcomposite,
  libXcursor,
  libXdamage,
  libXext,
  libXfixes,
  libXi,
  libXrandr,
  libXrender,
  libXtst,
  libxcb,
  libXau,
  libXdmcp,
  libglvnd,
  libgbm,
  mesa,
  ...
}:

{
  version ? "0.10.14",
  sha256 ? "07b0r02qv50ckfkmq5w9r1vnhldg01hffz9hx2gl1x1dq3g39kpz",
  releaseTag ? version,
}:
let
  release = fetchzip {
    name = "logseq-${version}-binary";
    url = "https://github.com/logseq/logseq/releases/download/${releaseTag}/Logseq-linux-x64-${version}.zip";
    inherit sha256;
  };

  desktopItem = makeDesktopItem {
    name = "logseq";
    desktopName = "Logseq";
    exec = "logseq-fhs %U";
    terminal = false;
    icon = "logseq";
    startupWMClass = "Logseq";
    comment = "Privacy-first knowledge base";
    mimeTypes = [ "x-scheme-handler/logseq" ];
    categories = [
      "Utility"
      "Office"
    ];
  };

  logseqUnwrapped = stdenv.mkDerivation {
    pname = "logseq-unwrapped";
    inherit version;
    src = release;

    sourceRoot = ".";
    nativeBuildInputs = [ copyDesktopItems ];
    desktopItems = [ desktopItem ];
    dontFixup = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/share/logseq"
      shopt -s dotglob
      cp -r ./* "$out/share/logseq/"
      shopt -u dotglob

      # Some upstream archives place the full tree under a release-named
      # directory (e.g. "logseq-<ver>-binary/Logseq-linux-x64"). Flatten any
      # such staging folder so the wrapper can discover the binary at
      # "$out/share/logseq/Logseq".
      shopt -s nullglob
      for stage_dir in "$out/share/logseq"/logseq-*; do
        if [ -d "''${stage_dir}/Logseq-linux-x64" ]; then
          shopt -s dotglob
          mv "''${stage_dir}/Logseq-linux-x64"/* "$out/share/logseq/"
          shopt -u dotglob
          rm -rf "''${stage_dir}"
        fi
      done

      if [ -d "$out/share/logseq/Logseq-linux-x64" ]; then
        shopt -s dotglob
        mv "$out/share/logseq/Logseq-linux-x64"/* "$out/share/logseq/"
        shopt -u dotglob
        rm -rf "$out/share/logseq/Logseq-linux-x64"
      fi
      shopt -u nullglob

      # remove auto-update scaffolding if present
      rm -f "$out/share/logseq/resources/app/update.js"
      rm -f "$out/share/logseq/resources/app/app-update.yml"

      if [ -f "$out/share/logseq/resources/app/icon.png" ]; then
        install -Dm644 "$out/share/logseq/resources/app/icon.png" \
          "$out/share/icons/hicolor/512x512/apps/logseq.png"
      fi

      runHook postInstall
    '';

    meta = {
      description = "Logseq binary release repackaged for Nix";
      homepage = "https://logseq.com";
      license = lib.licenses.agpl3Only;
      platforms = [ "x86_64-linux" ];
    };
  };

  runtimePackages = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    dejavu_fonts
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    harfbuzz
    krb5
    libappindicator-gtk3
    libdrm
    libnotify
    libpulseaudio
    libsecret
    libuuid
    libxkbcommon
    nspr
    nss
    pango
    pipewire
    udev
    xdg-desktop-portal
    xdg-user-dirs
    xdg-utils
    zlib
    libX11
    libXScrnSaver
    libXcomposite
    libXcursor
    libXdamage
    libXext
    libXfixes
    libXi
    libXrandr
    libXrender
    libXtst
    libxcb
    libXau
    libXdmcp
    libglvnd
    libgbm
    mesa
  ];

  runtimeLauncher = writeShellScriptBin "logseq-fhs-runtime" ''
    STORE_ROOT=${logseqUnwrapped}/share/logseq
    export ELECTRON_DISABLE_SECURITY_WARNINGS=1
    export ELECTRON_IS_DEV=0
    export NIXOS_OZONE_WL="''${NIXOS_OZONE_WL:-1}"
    export GTK_USE_PORTAL=1
    if [ ! -x "$STORE_ROOT/Logseq" ]; then
      echo "logseq-fhs-runtime: expected binary at $STORE_ROOT/Logseq" >&2
      echo "Found the following contents:" >&2
      ls "$STORE_ROOT" >&2
      exit 1
    fi

    exec "$STORE_ROOT/Logseq" --disable-setuid-sandbox "$@"
  '';

  logseqFhs = buildFHSEnv {
    name = "logseq-fhs";
    targetPkgs = _: runtimePackages;
    runScript = "${runtimeLauncher}/bin/logseq-fhs-runtime";
    extraInstallCommands = ''
      mkdir -p $out/share/icons/hicolor/512x512/apps
      ln -sf ${logseqUnwrapped}/share/icons/hicolor/512x512/apps/logseq.png \
        $out/share/icons/hicolor/512x512/apps/logseq.png
      mkdir -p $out/share/applications
      ln -sf ${logseqUnwrapped}/share/applications/logseq.desktop \
        $out/share/applications/logseq.desktop
      mkdir -p $out/bin
      ln -sf logseq-fhs $out/bin/logseq
    '';
  };

in
{
  "logseq-unwrapped" = logseqUnwrapped;
  "logseq-fhs" = logseqFhs;
}
