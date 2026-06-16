{
  lib,
  symlinkJoin,
  stdenvNoCC,
  writeShellApplication,
  makeDesktopItem,
  copyDesktopItems,
  imagemagick,
  electron,
  xdg-utils,
  glib-networking,
  cacert,
  coreutils,
}:

let
  version = "0-unstable";

  # Source icon is a 128x128 raster, so only downscale to standard sizes.
  # Upscaling beyond 128 would blur, so the icon set stops at the native size.
  iconSizes = [
    16
    22
    24
    32
    48
    64
    128
  ];

  # Electron app files shipped as a real package directory instead of inline
  # heredocs, so main.js stays lintable JavaScript and keeps the external-link
  # routing logic readable.
  app = stdenvNoCC.mkDerivation {
    pname = "raindrop-app";
    inherit version;

    dontUnpack = true;

    installPhase = ''
      runHook preInstall

      install -Dm644 ${./main.js} $out/share/raindrop/main.js
      install -Dm644 ${./package.json} $out/share/raindrop/package.json

      runHook postInstall
    '';
  };

  launcher = writeShellApplication {
    name = "raindrop";

    runtimeInputs = [
      electron
      xdg-utils
      coreutils
    ];

    runtimeEnv = {
      GIO_EXTRA_MODULES = "${glib-networking}/lib/gio/modules";
      SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    };

    text = /* bash */ ''
      # XDG Base Directory compliant profile path. Electron defaults to
      # ~/.config/<app>, so keep config semantics. Using := handles both unset
      # AND empty cases (unlike :- which only handles unset).
      : "''${XDG_CONFIG_HOME:=$HOME/.config}"
      profile="$XDG_CONFIG_HOME/raindrop"
      mkdir -p "$profile"

      exec electron \
        --ozone-platform-hint=auto \
        --enable-features=UseOzonePlatform,WaylandWindowDecorations \
        --class=Raindrop \
        --name=Raindrop \
        --user-data-dir="$profile" \
        ${app}/share/raindrop "$@"
    '';
  };

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
    startupNotify = true;
  };

  # Icons and desktop file assets.
  assets = stdenvNoCC.mkDerivation {
    pname = "raindrop-assets";
    inherit version;

    dontUnpack = true;

    nativeBuildInputs = [
      copyDesktopItems
      imagemagick
    ];

    desktopItems = [ desktopItem ];

    installPhase = ''
      runHook preInstall

      # Generate PNG icons at standard sizes (downscaled from the 128x128 source).
      ${lib.concatMapStringsSep "\n" (size: ''
        mkdir -p $out/share/icons/hicolor/${toString size}x${toString size}/apps
        magick ${./raindrop-io-icon-128.png} -resize ${toString size}x${toString size} \
          $out/share/icons/hicolor/${toString size}x${toString size}/apps/raindrop.png
      '') iconSizes}

      runHook postInstall
    '';
  };

in
symlinkJoin {
  name = "raindrop-${version}";
  paths = [
    launcher
    assets
  ];

  passthru = {
    inherit
      app
      launcher
      assets
      ;
  };

  meta = {
    description = "Electron wrapper for the Raindrop.io bookmark manager";
    longDescription = ''
      A dedicated Electron window for the Raindrop.io bookmark manager.

      Features:
      - Isolated profile under XDG_CONFIG_HOME/raindrop so sessions and bookmarks
        stay separate from other Electron apps.
      - External top-level navigations and window.open targets open in the
        default system browser, while raindrop.io and a fixed set of social
        sign-in hosts (Google, Apple, Facebook, X/Twitter) stay in the app
        window so OAuth flows complete in the app profile.
    '';
    homepage = "https://raindrop.io";
    license = lib.licenses.mit;
    mainProgram = "raindrop";
    platforms = lib.platforms.linux;
  };
}
