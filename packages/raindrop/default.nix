{
  lib,
  fetchurl,
  icoutils,
  makeDesktopItem,
  runCommand,
  coreutils,
  symlinkJoin,
  writeShellApplication,
  electron,
  xdg-utils,
  glib-networking,
  cacert,
}:
let
  iconIco = fetchurl {
    url = "https://raindrop.io/favicon.ico";
    hash = "sha256-110csvlzha8dg66qf3xzdj5v5wr36icfj7yg2fk0976s44cmhafp=";
  };
  iconPackage =
    runCommand "raindrop-icon"
      {
        nativeBuildInputs = [ icoutils ];
      }
      ''
        set -euo pipefail
        icotool -x -p 256 --output icons ${iconIco}
        mkdir -p "$out/share/icons/hicolor/256x256/apps"
        install -m644 icons/favicon_256x256x32.png "$out/share/icons/hicolor/256x256/apps/raindrop.png"
      '';
  desktopItem = makeDesktopItem {
    name = "raindrop";
    desktopName = "Raindrop.io";
    genericName = "Bookmark Manager";
    comment = "Access the Raindrop.io bookmark manager";
    exec = "raindrop";
    icon = "raindrop";
    categories = [
      "Network"
      "Office"
      "Utility"
    ];
    startupWMClass = "Raindrop";
  };
  desktopPackage = runCommand "raindrop-desktop" { } ''
    set -euo pipefail
    mkdir -p "$out/share/applications"
    cp ${desktopItem}/share/applications/*.desktop "$out/share/applications/"
  '';
  launcher = writeShellApplication {
    name = "raindrop";
    runtimeInputs = [
      electron
      xdg-utils
      glib-networking
      cacert
      coreutils
    ];
    text = ''
      set -euo pipefail
      profile="$HOME/.config/raindrop"
      if XDG_CONFIG_HOME_VALUE="$(printenv XDG_CONFIG_HOME 2>/dev/null)"; then
        if [ -n "$XDG_CONFIG_HOME_VALUE" ]; then
          profile="$XDG_CONFIG_HOME_VALUE/raindrop"
        fi
      fi
      mkdir -p "$profile"
      exec ${electron}/bin/electron \
        --ozone-platform=auto \
        --enable-features=UseOzonePlatform,WaylandWindowDecorations \
        --class=Raindrop \
        --name=Raindrop \
        --user-data-dir="$profile" \
        --app=https://app.raindrop.io "$@"
    '';
  };
  joined = symlinkJoin {
    name = "raindrop";
    paths = [
      launcher
      iconPackage
      desktopPackage
    ];
  };
in
joined.overrideAttrs (old: {
  meta = (old.meta or { }) // {
    description = "Electron wrapper for the Raindrop.io bookmark manager";
    homepage = "https://raindrop.io";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "raindrop";
  };
})
