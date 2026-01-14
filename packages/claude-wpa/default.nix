{
  lib,
  symlinkJoin,
  stdenvNoCC,
  writeShellApplication,
  makeDesktopItem,
  copyDesktopItems,
  ungoogled-chromium,
  librsvg,
  glib-networking,
  cacert,
  coreutils,
  # Configurable arguments
  extraExtensionPaths ? [ ],
  extraFlags ? [ ],
  profileName ? "claude-wpa",
}:

let
  version = "0.1.0";

  # Extension loading (user-provided only)
  extensionPathsStr = lib.concatStringsSep "," extraExtensionPaths;
  hasExtensions = extraExtensionPaths != [ ];

  iconSizes = [
    16
    22
    24
    32
    48
    64
    128
    256
    512
  ];

  # Base Chromium flags for app mode
  baseFlags = [
    # App mode configuration
    "--app=https://claude.ai"
    "--class=claude-wpa"
    "--name=Claude.ai WPA"
    # Wayland/X11 support (platform set dynamically in script)
    "--enable-features=UseOzonePlatform,WaylandWindowDecorations,OverlayScrollbar"
    "--disable-features=OverscrollHistoryNavigation"
    # UI preferences
    "--force-dark-mode"
    # Startup performance (GPU sandbox kept for security)
    "--disable-background-timer-throttling"
    "--disable-renderer-backgrounding"
    "--disable-component-update"
    "--in-process-gpu"
    # Privacy hardening (ungoogled-chromium recommended)
    "--disable-background-networking"
    "--disable-breakpad"
    "--disable-client-side-phishing-detection"
    "--disable-domain-reliability"
    "--no-pings"
    # Clean app experience
    "--disable-default-apps"
    "--disable-sync"
    "--no-first-run"
  ];

  # Combine base flags with extras
  allFlags = baseFlags ++ extraFlags;

  # Extension loading flag (only if extensions are provided)
  extensionFlag = lib.optionalString hasExtensions ''--load-extension="${extensionPathsStr}"'';

  # Launcher script using writeShellApplication (idiomatic Nix pattern)
  launcher = writeShellApplication {
    name = "claude-wpa";

    runtimeInputs = [
      ungoogled-chromium
      coreutils
    ];

    runtimeEnv = {
      GIO_EXTRA_MODULES = "${glib-networking}/lib/gio/modules";
      SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    };

    text = ''
      # XDG Base Directory compliant profile path
      # Using := handles both unset AND empty cases (unlike :- which only handles unset)
      : "''${XDG_DATA_HOME:=$HOME/.local/share}"
      profile="$XDG_DATA_HOME/${profileName}"
      mkdir -p "$profile"

      # Detect display server for faster startup (avoid auto-detection delay)
      case "''${XDG_SESSION_TYPE:-x11}" in
        wayland) ozone_platform="wayland" ;;
        *)       ozone_platform="x11" ;;
      esac

      # Handle claude-wpa:// protocol URLs
      url=""
      args=()
      for arg in "$@"; do
        if [[ "$arg" == claude-wpa://* ]]; then
          # Convert claude-wpa://path to https://claude.ai/path
          path="''${arg#claude-wpa://}"
          url="https://claude.ai/$path"
        else
          args+=("$arg")
        fi
      done

      # If a protocol URL was provided, add it as the target
      if [[ -n "$url" ]]; then
        args+=("$url")
      fi

      exec chromium \
        --user-data-dir="$profile" \
        --ozone-platform="$ozone_platform" \
        ${extensionFlag} \
        ${lib.concatStringsSep " \\\n        " allFlags} \
        ''${args[@]+"''${args[@]}"}
    '';
  };

  desktopItem = makeDesktopItem {
    name = "claude-wpa";
    desktopName = "Claude.ai WPA";
    genericName = "AI Assistant";
    comment = "Claude AI Web Progressive App";
    exec = "claude-wpa %U";
    icon = "claude-wpa";
    categories = [
      "Utility"
      "Development"
    ];
    startupWMClass = "claude-wpa";
    startupNotify = true;
    mimeTypes = [ "x-scheme-handler/claude-wpa" ];
  };

  # Icons and desktop file assets
  assets = stdenvNoCC.mkDerivation {
    pname = "claude-wpa-assets";
    inherit version;

    dontUnpack = true;

    nativeBuildInputs = [
      copyDesktopItems
      librsvg
    ];

    desktopItems = [ desktopItem ];

    installPhase = ''
      runHook preInstall

      # Install scalable SVG icon
      install -Dm644 ${./icon.svg} $out/share/icons/hicolor/scalable/apps/claude-wpa.svg

      # Generate PNG icons at standard sizes
      ${lib.concatMapStringsSep "\n" (size: ''
        mkdir -p $out/share/icons/hicolor/${toString size}x${toString size}/apps
        rsvg-convert -w ${toString size} -h ${toString size} \
          ${./icon.svg} > $out/share/icons/hicolor/${toString size}x${toString size}/apps/claude-wpa.png
      '') iconSizes}

      runHook postInstall
    '';
  };

in
symlinkJoin {
  name = "claude-wpa-${version}";
  paths = [
    launcher
    assets
  ];

  passthru = {
    inherit
      extraExtensionPaths
      allFlags
      launcher
      assets
      ;
  };

  meta = {
    description = "Claude AI Web Progressive App";
    longDescription = ''
      A containerized browser window for Claude AI using ungoogled-chromium in app mode.

      Features:
      - Isolated profile directory following XDG Base Directory specification
      - Custom protocol handler (claude-wpa://) for deep linking
      - Overlay scrollbars and minimal browser chrome
      - External links automatically open in the default system browser
    '';
    homepage = "https://claude.ai";
    license = lib.licenses.agpl3Plus;
    mainProgram = "claude-wpa";
    platforms = lib.platforms.linux;
  };
}
