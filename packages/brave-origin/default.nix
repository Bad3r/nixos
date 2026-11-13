# Carried from nixpkgs after NixOS/nixpkgs 73120ec5921e dropped brave and brave-origin.
{
  lib,
  stdenv,
  fetchurl,
  buildPackages,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  dpkg,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  adwaita-icon-theme,
  gsettings-desktop-schemas,
  gtk3,
  gtk4,
  qt6,
  libx11,
  libxscrnsaver,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxrandr,
  libxrender,
  libxtst,
  libdrm,
  libkrb5,
  libuuid,
  libxkbcommon,
  libxshmfence,
  libgbm,
  nspr,
  nss,
  pango,
  pciutils,
  pipewire,
  snappy,
  speechd-minimal,
  udev,
  wayland,
  xdg-utils,
  coreutils,
  libxcb,
  vulkan-loader,
  zlib,
  libpulseaudio,
  libGL,
  libva,
  # always-set command line arguments, e.g. "--disable-gpu"
  commandLineArgs ? "",
  pulseSupport ? true,
  libvaSupport ? true,
  enableVideoAcceleration ? libvaSupport,
  # Vulkan breaks VA-API, so it stays off by default
  enableVulkan ? false,
}:

let
  pname = "brave-origin";
  version = "1.99.56";

  sources = {
    x86_64-linux = fetchurl {
      url = "https://github.com/brave/brave-browser/releases/download/v${version}/brave-origin_${version}_amd64.deb";
      hash = "sha256-tamLNby63nb9MrOzIkHdKGzGXvRSrlnczx8NrAJne68=";
    };
    aarch64-linux = fetchurl {
      url = "https://github.com/brave/brave-browser/releases/download/v${version}/brave-origin_${version}_arm64.deb";
      hash = "sha256-YXDY/Tz5KOwVJ0PSzykNCLdZjW2E8DzZtUCASacWny0=";
    };
  };

  optDir = "opt/brave.com/brave-origin";

  deps = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    gtk4
    libdrm
    libx11
    libGL
    libxkbcommon
    libxscrnsaver
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxshmfence
    libxtst
    libuuid
    libgbm
    nspr
    nss
    pango
    pciutils # ANGLE dlopens libpci for GPU and VA-API device selection
    pipewire
    udev
    wayland
    libxcb
    zlib
    snappy
    speechd-minimal
    libkrb5
    vulkan-loader # dlopened by name as libvulkan.so.1
    qt6.qtbase
  ]
  ++ lib.optional pulseSupport libpulseaudio
  ++ lib.optional libvaSupport libva;

  rpath = lib.makeLibraryPath deps + ":" + lib.makeSearchPathOutput "lib" "lib64" deps;

  enableFeatures =
    lib.optionals enableVideoAcceleration [
      "AcceleratedVideoDecodeLinuxGL"
      "AcceleratedVideoEncoder"
    ]
    ++ lib.optional enableVulkan "Vulkan";

  disableFeatures = [
    "OutdatedBuildDetector"
  ]
  # https://github.com/brave/brave-browser/issues/20935
  ++ lib.optional enableVideoAcceleration "UseChromeOSDirectVideoDecoder";
in
stdenv.mkDerivation {
  inherit pname version;

  __structuredAttrs = true;
  strictDeps = true;

  src =
    sources.${stdenv.hostPlatform.system}
      or (throw "${pname} is not available for ${stdenv.hostPlatform.system}");

  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  doInstallCheck = true;

  nativeBuildInputs = [
    dpkg
    # override drops splicing (NixOS/nixpkgs#132651), so take the wrapper from buildPackages
    (buildPackages.wrapGAppsHook3.override { makeWrapper = buildPackages.makeShellWrapper; })
  ];

  buildInputs = [
    # GSETTINGS_SCHEMAS_PATH
    glib
    gsettings-desktop-schemas
    gtk3
    gtk4
    # XDG_ICON_DIRS
    adwaita-icon-theme
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -R usr/share $out
    cp -R opt/ $out/opt

    wrapper=$out/${optDir}/brave-origin
    substituteInPlace $wrapper \
      --replace-fail /bin/bash ${stdenv.shell} \
      --replace-fail 'CHROME_WRAPPER' 'WRAPPER'
    ln -sf $wrapper $out/bin/${pname}

    for exe in $out/${optDir}/{brave,chrome_crashpad_handler}; do
      patchelf \
        --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
        --set-rpath "${rpath}" $exe
    done

    substituteInPlace $out/share/applications/{brave-origin,com.brave.Origin}.desktop \
      --replace-fail /usr/bin/brave-origin-stable $out/bin/${pname}
    substituteInPlace $out/share/gnome-control-center/default-apps/brave-origin.xml \
      --replace-fail /opt/brave.com $out/opt/brave.com
    substituteInPlace $out/${optDir}/default-app-block \
      --replace-fail /opt/brave.com $out/opt/brave.com

    for size in 16 24 32 48 64 128 256; do
      mkdir -p $out/share/icons/hicolor/''${size}x''${size}/apps
      ln -s $out/${optDir}/product_logo_''${size}.png \
        $out/share/icons/hicolor/''${size}x''${size}/apps/brave-origin.png
    done

    # ANGLE loads this copy by absolute path; only the NixOS loader finds ICDs under /run/opengl-driver
    rm $out/${optDir}/libvulkan.so.1
    ln -s ${lib.getLib vulkan-loader}/lib/libvulkan.so.1 $out/${optDir}/libvulkan.so.1

    ln -sf ${xdg-utils}/bin/xdg-settings $out/${optDir}/xdg-settings
    ln -sf ${xdg-utils}/bin/xdg-mime $out/${optDir}/xdg-mime

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : ${rpath}
      --prefix PATH : ${lib.makeBinPath deps}
      --suffix PATH : ${
        lib.makeBinPath [
          xdg-utils
          coreutils
        ]
      }
      --set CHROME_WRAPPER ${pname}
      ${lib.optionalString (enableFeatures != [ ]) ''
        --add-flags "--enable-features=${lib.concatStringsSep "," enableFeatures}\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+,WaylandWindowDecorations --enable-wayland-ime=true}}"
      ''}
      --add-flags "--disable-features=${lib.concatStringsSep "," disableFeatures}"
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto}}"
      --add-flags ${lib.escapeShellArg commandLineArgs}
    )
  '';

  installCheckPhase = ''
    # the upstream wrapper suppresses errors
    $out/${optDir}/brave --version
  '';

  passthru.updateScript = ./update.py;

  meta = {
    description = "Brave browser variant with rewards, wallet, and AI features removed";
    homepage = "https://brave.com/origin/";
    changelog = "https://github.com/brave/brave-browser/blob/master/CHANGELOG_DESKTOP_ORIGIN.md";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.mpl20;
    platforms = lib.attrNames sources;
    mainProgram = "brave-origin";
  };
}
