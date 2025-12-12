{
  lib,
  stdenv,
  pkgs,
  makeWrapper,
  makeDesktopItem,
  fetchurl,
  temurin-bin-21,
  jdk11,
  jdk8,
}:
# Performance Tuning for Temurin JDK 21 (Eclipse Adoptium)
# Optimized for powerful systems (24GB+ RAM) running demanding proxy workloads
# Official ZGC docs: https://docs.oracle.com/en/java/javase/21/gctuning/z-garbage-collector.html
# JDK 21 adds Generational ZGC for better Swing object allocation performance
#
# Memory Allocation (configurable via parameters):
#   Heap:          8GB committed (Xms/Xmx=8192M), targets 6GB via SoftMaxHeapSize
#   Direct Memory: 4GB (directMemorySize=4096M) - critical for NIO proxy traffic
#   Metaspace:     512M-2GB (metaspaceSize/maxMetaspaceSize)
#   Code Cache:    1GB (codeCacheSize=1024m)
#   Total:         ~16GB allocated, ~13GB typical usage
#
# Garbage Collection:
#   ZGC (Charles 5.x): Sub-millisecond pause times, concurrent, generational (JDK 21)
#     Flags: -XX:+UseZGC -XX:+ZGenerational -XX:+UseNUMA
#            -XX:ZAllocationSpikeTolerance=2 -XX:ZCollectionInterval=5 -XX:ZFragmentationLimit=25
#     Generational mode reduces memory overhead and improves throughput for Swing's allocation patterns
#   G1GC (Charles 3.x/4.x): 150ms max pause, optimized for 8GB heap
#     Flags: -XX:+UseG1GC -XX:+UseStringDeduplication -XX:MaxGCPauseMillis=150
#            -XX:G1HeapRegionSize=32M -XX:InitiatingHeapOccupancyPercent=45
#
# Key Performance Flags:
#   -XX:+AlwaysPreTouch              Pre-touch all heap at startup (eliminates runtime page faults)
#   -XX:+DisableExplicitGC           Prevent System.gc() calls
#   -Djdk.nio.maxCachedBufferSize   1MB per-thread NIO buffer cache
#   -Xss4m                           4MB thread stacks for deep call stacks
#   -Dawt.useSystemAAFontSettings    Use system font antialiasing settings
#   -XX:+PrintCommandLineFlags       Show applied JVM flags at startup
#   -Xlog:gc*                        Detailed GC logging to /tmp/charles-gc.log
#
# Note: Java 17 Swing rendering relies on native X11 libraries (provided via extraLdLibraryPath)
# for hardware acceleration. The old sun.java2d.opengl/xrender flags are deprecated/removed.

let
  generic =
    attrs@{
      version,
      hash,
      platform ? "",
      jdk ? null,
      useBundledLauncher ? false,
      heapSize ? "8192M",
      directMemorySize ? "4096M",
      metaspaceSize ? "512M",
      maxMetaspaceSize ? "2048M",
      codeCacheSize ? "1024m",
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
          ${
            lib.optionalString (libPath != "") ''--prefix LD_LIBRARY_PATH : ${lib.escapeShellArg libPath}''
          } \
          --set-default JAVA_TOOL_OPTIONS "-XX:MaxDirectMemorySize=${directMemorySize} -XX:MetaspaceSize=${metaspaceSize} -XX:MaxMetaspaceSize=${maxMetaspaceSize} -XX:ReservedCodeCacheSize=${codeCacheSize} -XX:SoftRefLRUPolicyMSPerMB=50 -Xss4m -XX:+DisableExplicitGC -Djdk.nio.maxCachedBufferSize=1048576"
      ''
      + lib.optionalString (!useBundled) ''
        makeWrapper ${jdk}/bin/java $out/bin/charles \
          ${
            lib.optionalString (libPath != "") ''--prefix LD_LIBRARY_PATH : ${lib.escapeShellArg libPath}''
          } \
          --add-flags "-Xms${heapSize} -Xmx${heapSize} -XX:SoftMaxHeapSize=6144M -XX:MaxDirectMemorySize=${directMemorySize} -XX:MetaspaceSize=${metaspaceSize} -XX:MaxMetaspaceSize=${maxMetaspaceSize} -XX:ReservedCodeCacheSize=${codeCacheSize} -XX:SoftRefLRUPolicyMSPerMB=50 -Xss4m -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -Djdk.nio.maxCachedBufferSize=1048576 -Djava.awt.headless=false -Dawt.useSystemAAFontSettings=on -XX:+PrintCommandLineFlags -Xlog:gc*:file=/tmp/charles-gc.log:time,level,tags ${lib.optionalString (lib.versionOlder version "5.0") "-XX:+UseG1GC -XX:+UseStringDeduplication -XX:MaxGCPauseMillis=150 -XX:G1HeapRegionSize=32M -XX:InitiatingHeapOccupancyPercent=45"} ${lib.optionalString (lib.versionAtLeast version "5.0") "-XX:+UseZGC -XX:+ZGenerational -XX:+UseNUMA -XX:ZAllocationSpikeTolerance=2 -XX:ZCollectionInterval=5 -XX:ZFragmentationLimit=25"} -Dcharles.config='~/.charles.config' ${lib.optionalString (lib.versionOlder version "5.0") "-jar $out/share/java/charles.jar"} ${lib.optionalString (lib.versionAtLeast version "5.0") "-Djava.library.path='$out/share/java' --add-opens java.base/sun.security.ssl=com.charlesproxy --add-opens java.desktop/java.awt.event=com.charlesproxy --add-opens java.base/java.io=com.charlesproxy --add-modules com.jthemedetector,com.formdev.flatlaf --module-path '$out/share/java' -m com.charlesproxy"}"

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
  # Charles 5 with system Java (RECOMMENDED for better performance)
  # Uses Temurin JDK 21 (Eclipse Adoptium) instead of bundled launcher
  # Includes native libraries for GPU-accelerated rendering (CRITICAL for UI performance)
  # JDK 21 improvements: Generational ZGC, better Swing performance, improved JIT
  charles5-system-java = generic {
    version = "5.0.3";
    hash = "sha256-SiZ15ekuAW7AyXBHN5Zel4ZFL/4oNy1td64NQ0GNUhE=";
    platform = "_x86_64";
    useBundledLauncher = false;
    jdk = temurin-bin-21;
    # Native libraries for hardware-accelerated graphics rendering
    # Without these, Charles uses software rendering which is EXTREMELY slow
    extraLdLibraryPath = map lib.getLib (
      (with pkgs; [
        alsa-lib
        cups
        fontconfig
        freetype
        glib
        libdrm
        libglvnd # OpenGL vendor-neutral dispatch
        mesa # Mesa 3D graphics
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

  # Charles 5 with bundled launcher (original, may be slower)
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
