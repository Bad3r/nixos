{
  lib,
  stdenv,
  pkgs,
  makeWrapper,
  makeDesktopItem,
  fetchurl,
  jdk11,
  jdk8,
}:

let
  generic =
    attrs@{
      version,
      hash,
      platform ? "",
      jdk ? null,
      useBundledLauncher ? false,
      ...
    }:
    let
      useBundled = useBundledLauncher;
      libPath = lib.makeLibraryPath (attrs.extraLdLibraryPath or [ ]);
      desktopItem = makeDesktopItem {
        categories = [
          "Network"
          "Development"
          "WebDevelopment"
          "Java"
        ];
        desktopName = "Charles";
        exec = "charles %F";
        genericName = "Web Debugging Proxy";
        icon = "charles-proxy";
        mimeTypes = [
          "application/x-charles-savedsession"
          "application/x-charles-savedsession+xml"
          "application/x-charles-savedsession+json"
          "application/har+json"
          "application/vnd.tcpdump.pcap"
          "application/x-charles-trace"
        ];
        name = "Charles";
        startupNotify = true;
      };

    in
    stdenv.mkDerivation {
      pname = "charles";
      inherit version;

      src = fetchurl {
        url = "https://www.charlesproxy.com/assets/release/${version}/charles-proxy-${version}${platform}.tar.gz";
        curlOptsList = [
          "--user-agent"
          "Mozilla/5.0"
        ]; # HTTP 104 otherwise
        inherit hash;
      };

      nativeBuildInputs = [ makeWrapper ];

      installPhase = ''
        runHook preInstall

      ''
      + lib.optionalString useBundled ''
        install -d $out/libexec
        cp -r . $out/libexec/charles
        makeWrapper $out/libexec/charles/bin/charles $out/bin/charles \
          ${lib.optionalString (libPath != "") ''--prefix LD_LIBRARY_PATH : ${lib.escapeShellArg libPath}''}
      ''
      + lib.optionalString (!useBundled) ''
        makeWrapper ${jdk}/bin/java $out/bin/charles \
          --add-flags "-Xmx1024M -Dcharles.config='~/.charles.config' ${lib.optionalString (lib.versionOlder version "5.0") "-jar $out/share/java/charles.jar"} ${lib.optionalString (lib.versionAtLeast version "5.0") "-XX:+UseZGC -Djava.library.path='$out/share/java' --add-opens java.base/sun.security.ssl=com.charlesproxy --add-opens java.desktop/java.awt.event=com.charlesproxy --add-opens java.base/java.io=com.charlesproxy --add-modules com.jthemedetector,com.formdev.flatlaf --module-path '$out/share/java' -m com.charlesproxy"}"

        for fn in lib/*.jar; do
          install -D -m644 $fn $out/share/java/$(basename $fn)
        done
      ''
      + ''
        mkdir -p $out/share/applications
        ln -s ${desktopItem}/share/applications/* $out/share/applications/

        mkdir -p $out/share/icons
        cp -r icon $out/share/icons/hicolor

        runHook postInstall
      '';

      meta = {
        description = "Web Debugging Proxy";
        homepage = "https://www.charlesproxy.com/";
        maintainers = with lib.maintainers; [
          kalbasit
          kashw2
        ];
        sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
        license = lib.licenses.unfree;
        platforms = lib.platforms.unix;
      };
    };

in
{
  charles5 = generic {
    version = "5.0.3";
    hash = "sha256-SiZ15ekuAW7AyXBHN5Zel4ZFL/4oNy1td64NQ0GNUhE=";
    platform = "_x86_64";
    useBundledLauncher = true;
    extraLdLibraryPath = map lib.getLib (
      (with pkgs; [
        alsa-lib
        cups
        fontconfig
        freetype
        glib
        libdrm
        libglvnd
        mesa
        nss
        stdenv.cc.cc
        zlib
      ])
      ++ (with pkgs.xorg; [
        libX11
        libXau
        libXcomposite
        libXcursor
        libXdamage
        libXdmcp
        libXext
        libXfixes
        libXi
        libXinerama
        libXrandr
        libXrender
        libXtst
        libxcb
      ])
    );
  };
  charles4 = generic {
    version = "4.6.8";
    hash = "sha256-AaS+zmQTWsGoLEhyGHA/UojmctE7IV0N9fnygNhEPls=";
    platform = "_amd64";
    jdk = jdk11;
  };
  charles3 = generic {
    version = "3.12.3";
    hash = "sha256-Wotxzf6kutYv1F6q71eJVojVJsATJ81war/w4K1A848=";
    jdk = jdk8.jre;
    mainProgram = "charles";
  };
}
