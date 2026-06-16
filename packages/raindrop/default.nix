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
    mkdir -p $out/share/raindrop

    cat > $out/share/raindrop/package.json <<'JSON'
    {
      "name": "raindrop",
      "version": "0.0.0",
      "main": "main.js"
    }
    JSON

    cat > $out/share/raindrop/main.js <<'APP'
    const { app, BrowserWindow, shell } = require("electron");

    const raindropHost = "raindrop.io";
    const externalProtocols = new Set(["http:", "https:", "mailto:", "tel:"]);

    function parseUrl(rawUrl) {
      try {
        return new URL(rawUrl);
      } catch (error) {
        console.error("Blocked invalid URL " + rawUrl + ": " + error.message);
        return null;
      }
    }

    function isRaindropUrl(rawUrl) {
      const url = parseUrl(rawUrl);
      if (url === null) {
        return false;
      }

      return (
        (url.protocol === "http:" || url.protocol === "https:") &&
        (url.hostname === raindropHost || url.hostname.endsWith("." + raindropHost))
      );
    }

    function openExternal(rawUrl) {
      const url = parseUrl(rawUrl);
      if (url === null) {
        return;
      }

      if (!externalProtocols.has(url.protocol)) {
        console.error("Blocked unsupported external URL scheme: " + url.protocol);
        return;
      }

      shell.openExternal(url.href).catch((error) => {
        console.error("Failed to open external URL " + url.href + ": " + error.message);
      });
    }

    function createWindow() {
      const window = new BrowserWindow({
        width: 1280,
        height: 900,
        title: "Raindrop.io",
        webPreferences: {
          contextIsolation: true,
          nodeIntegration: false,
          sandbox: true,
        },
      });

      window.webContents.setWindowOpenHandler(({ url }) => {
        if (isRaindropUrl(url)) {
          window.loadURL(url);
        } else {
          openExternal(url);
        }

        return { action: "deny" };
      });

      // Top-level navigations are left untouched so OAuth provider redirects
      // (Google, Apple, Facebook, Twitter) and payment flows complete inside
      // this window, where their session cookies reach the Electron
      // --user-data-dir profile. Only new-window requests (target=_blank
      // bookmark links) are routed to the default browser, by the handler
      // above. Intercepting will-navigate here would break social sign-in.
      window.loadURL("https://app.raindrop.io");
    }

    app.whenReady().then(() => {
      createWindow();

      app.on("activate", () => {
        if (BrowserWindow.getAllWindows().length === 0) {
          createWindow();
        }
      });
    });

    app.on("window-all-closed", () => {
      if (process.platform !== "darwin") {
        app.quit();
      }
    });
    APP

    cat > $out/bin/raindrop <<'LAUNCHER'
    #!/usr/bin/env bash
    set -euo pipefail
    app_dir="@raindropAppDir@"
    profile="$HOME/.config/raindrop"
    if XDG_CONFIG_HOME_VALUE="$(printenv XDG_CONFIG_HOME 2>/dev/null)"; then
      if [ -n "$XDG_CONFIG_HOME_VALUE" ]; then
        profile="$XDG_CONFIG_HOME_VALUE/raindrop"
      fi
    fi
    mkdir -p "$profile"
    exec electron \
      --ozone-platform-hint=auto \
      --enable-features=UseOzonePlatform,WaylandWindowDecorations \
      --class=Raindrop \
      --name=Raindrop \
      --user-data-dir="$profile" \
      "$app_dir" "$@"
    LAUNCHER
    substituteInPlace $out/bin/raindrop \
      --replace-fail @raindropAppDir@ "$out/share/raindrop"
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
