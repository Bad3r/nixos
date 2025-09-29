_: {
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      java = pkgs.openjdk17;
      gsettingsSchemaDir = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}";
      xdgDataDirs = lib.makeSearchPath "share" [
        pkgs.gsettings-desktop-schemas
        pkgs.gtk3
        pkgs.gdk-pixbuf
        pkgs.glib
        pkgs.libnotify
        pkgs.libappindicator-gtk3
      ];
      runtimeLibs =
        with pkgs;
        [
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
        ]
        ++ (with pkgs.xorg; [
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
        ])
        ++ (with pkgs; [
          libglvnd
          libgbm
          mesa
        ]);
      buildTools = with pkgs; [
        nodejs_22
        yarn
        git
        git-lfs
        cacert
        clojure
        babashka
        java
        python3
        pkg-config
        gnumake
        gcc
        binutils
        nodePackages_latest.node-gyp-build
        p7zip
        unzip
        zip
        gnutar
        xz
        zstd
        fakeroot
        rpm
        dpkg
        xorriso
        patchelf
        chrpath
        fuse
        which
        openssl
      ];
    in
    {
      make-shells.logseq = {
        packages = buildTools ++ runtimeLibs;
        shellHook = ''
          export JAVA_HOME=${java}
          export GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          export ELECTRON_SKIP_BINARY_DOWNLOAD=1
          export LOGSEQ_DEV_SHELL=1
          export GSETTINGS_SCHEMA_DIR=${gsettingsSchemaDir}
          if [ -n "''${XDG_DATA_DIRS:-}" ]; then
            export XDG_DATA_DIRS=${xdgDataDirs}:$XDG_DATA_DIRS
          else
            export XDG_DATA_DIRS=${xdgDataDirs}
          fi
          echo "Logseq development shell loaded."
        '';
      };
    };
}
