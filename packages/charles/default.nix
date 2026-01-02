{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  makeDesktopItem,
  temurin-bin-21,
  # Native libraries for hardware-accelerated graphics rendering
  alsa-lib,
  cups,
  fontconfig,
  freetype,
  glib,
  libdrm,
  libglvnd,
  mesa,
  nss,
  zlib,
  # X11 libraries
  libX11,
  libXau,
  libXcomposite,
  libXcursor,
  libXdamage,
  libXdmcp,
  libXext,
  libXfixes,
  libXi,
  libXinerama,
  libXrandr,
  libXrender,
  libXtst,
  libxcb,
}:

# Performance Tuning for Temurin JDK 21 (Eclipse Adoptium)
# Optimized for powerful systems (24GB+ RAM) running demanding proxy workloads
# Official ZGC docs: https://docs.oracle.com/en/java/javase/21/gctuning/z-garbage-collector.html
# JDK 21 adds Generational ZGC for better Swing object allocation performance
#
# Memory Allocation:
#   Heap:          8GB committed (Xms/Xmx=8192M), targets 6GB via SoftMaxHeapSize
#   Direct Memory: 4GB (directMemorySize=4096M) - critical for NIO proxy traffic
#   Metaspace:     512M-2GB (metaspaceSize/maxMetaspaceSize)
#   Code Cache:    1GB (codeCacheSize=1024m)
#   Total:         ~16GB allocated, ~13GB typical usage
#
# Garbage Collection (ZGC):
#   Sub-millisecond pause times, concurrent, generational (JDK 21)
#   Generational mode reduces memory overhead and improves throughput for Swing's allocation patterns
#
# Key Performance Flags:
#   -XX:+AlwaysPreTouch              Pre-touch all heap at startup (eliminates runtime page faults)
#   -XX:+DisableExplicitGC           Prevent System.gc() calls
#   -Djdk.nio.maxCachedBufferSize   1MB per-thread NIO buffer cache
#   -Xss4m                           4MB thread stacks for deep call stacks
#   -Dawt.useSystemAAFontSettings    Use system font antialiasing settings
#
# Note: Java 17+ Swing rendering relies on native X11 libraries for hardware acceleration.

let
  version = "5.0.3";

  heapSize = "8192M";
  directMemorySize = "4096M";
  metaspaceSize = "512M";
  maxMetaspaceSize = "2048M";
  codeCacheSize = "1024m";

  jdk = temurin-bin-21;

  libPath = lib.makeLibraryPath [
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
  ];

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
    url = "https://www.charlesproxy.com/assets/release/${version}/charles-proxy-${version}_x86_64.tar.gz";
    curlOptsList = [
      "--user-agent"
      "Mozilla/5.0"
    ];
    hash = "sha256-SiZ15ekuAW7AyXBHN5Zel4ZFL/4oNy1td64NQ0GNUhE=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    makeWrapper ${jdk}/bin/java $out/bin/charles \
      --prefix LD_LIBRARY_PATH : ${lib.escapeShellArg libPath} \
      --add-flags "-Xms${heapSize} -Xmx${heapSize} -XX:SoftMaxHeapSize=6144M -XX:MaxDirectMemorySize=${directMemorySize} -XX:MetaspaceSize=${metaspaceSize} -XX:MaxMetaspaceSize=${maxMetaspaceSize} -XX:ReservedCodeCacheSize=${codeCacheSize} -XX:SoftRefLRUPolicyMSPerMB=50 -Xss4m -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -Djdk.nio.maxCachedBufferSize=1048576 -Djava.awt.headless=false -Dawt.useSystemAAFontSettings=on -XX:+PrintCommandLineFlags -Xlog:gc*:file=/tmp/charles-gc.log:time,level,tags -XX:+UseZGC -XX:+ZGenerational -XX:+UseNUMA -XX:ZAllocationSpikeTolerance=2 -XX:ZCollectionInterval=5 -XX:ZFragmentationLimit=25 -Dcharles.config='~/.charles.config' -Djava.library.path='\$out/share/java' --add-opens java.base/sun.security.ssl=com.charlesproxy --add-opens java.desktop/java.awt.event=com.charlesproxy --add-opens java.base/java.io=com.charlesproxy --add-modules com.jthemedetector,com.formdev.flatlaf --module-path '\$out/share/java' -m com.charlesproxy"

    for fn in lib/*.jar; do
      install -D -m644 $fn $out/share/java/$(basename $fn)
    done

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
    mainProgram = "charles";
    platforms = [ "x86_64-linux" ];
  };
}
