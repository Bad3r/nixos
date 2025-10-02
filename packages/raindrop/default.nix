{
  lib,
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

in
(symlinkJoin {
  name = "raindrop";
  paths = [
    launcher
    desktopPackage
  ];
}).overrideAttrs
  (old: {
    meta = (old.meta or { }) // {
      description = "Electron wrapper for the Raindrop.io bookmark manager";
      homepage = "https://raindrop.io";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = "raindrop";
    };
  })
