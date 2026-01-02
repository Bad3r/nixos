{
  lib,
  stdenvNoCC,
  makeWrapper,
  makeDesktopItem,
  electron,
  xdg-utils,
  glib-networking,
  cacert,
  coreutils,
}:

let
  desktopItem = makeDesktopItem {
    name = "raindrop";
    desktopName = "Raindrop.io";
    genericName = "Bookmark Manager";
    comment = "Access the Raindrop.io bookmark manager";
    exec = "raindrop";
    icon = "electron";
    categories = [
      "Network"
      "Office"
      "Utility"
    ];
    startupWMClass = "Raindrop";
  };
in
stdenvNoCC.mkDerivation {
  pname = "raindrop";
  version = "0-unstable";

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cat > $out/bin/raindrop <<'LAUNCHER'
    #!/usr/bin/env bash
    set -euo pipefail
    profile="$HOME/.config/raindrop"
    if XDG_CONFIG_HOME_VALUE="$(printenv XDG_CONFIG_HOME 2>/dev/null)"; then
      if [ -n "$XDG_CONFIG_HOME_VALUE" ]; then
        profile="$XDG_CONFIG_HOME_VALUE/raindrop"
      fi
    fi
    mkdir -p "$profile"
    exec electron \
      --ozone-platform=auto \
      --enable-features=UseOzonePlatform,WaylandWindowDecorations \
      --class=Raindrop \
      --name=Raindrop \
      --user-data-dir="$profile" \
      --app=https://app.raindrop.io "$@"
    LAUNCHER
    chmod +x $out/bin/raindrop

    wrapProgram $out/bin/raindrop \
      --prefix PATH : ${
        lib.makeBinPath [
          electron
          xdg-utils
          coreutils
        ]
      } \
      --prefix GIO_EXTRA_MODULES : "${glib-networking}/lib/gio/modules" \
      --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt"

    mkdir -p $out/share/applications
    ln -s ${desktopItem}/share/applications/* $out/share/applications/

    runHook postInstall
  '';

  meta = {
    description = "Electron wrapper for the Raindrop.io bookmark manager";
    homepage = "https://raindrop.io";
    license = lib.licenses.mit;
    mainProgram = "raindrop";
    platforms = lib.platforms.linux;
  };
}
