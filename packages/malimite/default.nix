{
  lib,
  stdenv,
  fetchzip,
  temurin-bin-21,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  ghidra ? null,
}:

stdenv.mkDerivation rec {
  pname = "malimite";
  version = "1.2";

  src = fetchzip {
    url = "https://github.com/LaurieWired/Malimite/releases/download/${version}/Malimite-${
      lib.replaceStrings [ "." ] [ "-" ] version
    }.zip";
    hash = "sha256-ne0/gOZPsGkjhJlWjhbcUTOu2SR34/lBFhQDKh4yNoc=";
    stripRoot = false;
  };

  nativeBuildInputs = [
    makeWrapper
    copyDesktopItems
    temurin-bin-21
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Create directory structure
    mkdir -p $out/{bin,share/malimite,share/icons/hicolor/256x256/apps}

    # Install the JAR and DecompilerBridge directory
    cp -r ./* $out/share/malimite/

    # Create template config file with Ghidra path if available
    ${lib.optionalString (ghidra != null) ''
            cat > $out/share/malimite/malimite.properties.template << EOF
      ghidra.path=${ghidra}/lib/ghidra
      app.theme=dark
      os.type=linux
      EOF
    ''}

    # Create wrapper script that sets up writable working directory
    # Malimite needs to write to malimite.properties and expects DecompilerBridge in cwd
    # Always regenerate config from template to ensure Ghidra path is current
    makeWrapper ${temurin-bin-21}/bin/java $out/bin/malimite \
      --add-flags "-Xms2G" \
      --add-flags "-Xmx8G" \
      --add-flags "-XX:+UseG1GC" \
      --add-flags "-XX:MaxGCPauseMillis=200" \
      --add-flags "-XX:+UseStringDeduplication" \
      --add-flags "-XX:+ParallelRefProcEnabled" \
      --add-flags "-XX:G1HeapRegionSize=16M" \
      --add-flags "-XX:InitiatingHeapOccupancyPercent=45" \
      --add-flags "-XX:ReservedCodeCacheSize=512M" \
      --add-flags "-XX:+UseCompressedOops" \
      --add-flags "-XX:+OptimizeStringConcat" \
      --add-flags "-XX:+AlwaysPreTouch" \
      --add-flags "-Dswing.aatext=true" \
      --add-flags "-Dawt.useSystemAAFontSettings=on" \
      --add-flags "-Dsun.java2d.xrender=true" \
      --add-flags "-Dswing.defaultlaf=com.formdev.flatlaf.FlatDarkLaf" \
      --add-flags "-Dflatlaf.defaultFont=MonoLisa" \
      --add-flags "-jar $out/share/malimite/Malimite-1-2.jar" \
      --run 'MALIMITE_HOME="$HOME/.local/share/malimite" && \
             mkdir -p "$MALIMITE_HOME" && \
             if [ ! -e "$MALIMITE_HOME/DecompilerBridge" ]; then \
               ln -sf "'"$out"'/share/malimite/DecompilerBridge" "$MALIMITE_HOME/DecompilerBridge"; \
             fi && \
             if [ -f "'"$out"'/share/malimite/malimite.properties.template" ]; then \
               install -m 644 "'"$out"'/share/malimite/malimite.properties.template" "$MALIMITE_HOME/malimite.properties"; \
             fi && \
             cd "$MALIMITE_HOME"'

    # Extract icon from JAR if needed (JAR files are ZIP files)
    mkdir -p $out/share/icons/hicolor/256x256/apps
    ${temurin-bin-21}/bin/jar xf $out/share/malimite/Malimite-1-2.jar icons/app-icon.png 2>/dev/null || true
    if [ -f icons/app-icon.png ]; then
      cp icons/app-icon.png $out/share/icons/hicolor/256x256/apps/malimite.png
      rm -rf icons
    fi

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "malimite";
      desktopName = "Malimite";
      comment = "iOS and macOS decompiler";
      exec = "malimite";
      icon = "malimite";
      categories = [
        "Development"
        "Debugger"
      ];
      terminal = false;
    })
  ];

  meta = {
    description = "iOS and macOS decompiler built on Ghidra";
    longDescription = ''
      Malimite is an iOS and macOS decompiler designed to help researchers
      analyze and decode IPA files and Application Bundles. Built on top of
      Ghidra decompilation to offer direct support for Swift, Objective-C,
      and Apple resources.

      Features:
      - Multi-Platform (Mac, Windows, Linux)
      - Direct support for IPA and bundle files
      - Auto decodes iOS resources
      - Avoids lib code decompilation
      - Reconstructs Swift classes
      - Built-in LLM method translation

      Note: When Ghidra is available in the system, the path is automatically
      pre-configured on first launch. Uses Java 21 LTS (Temurin) for optimal
      performance and compatibility.
    '';
    homepage = "https://github.com/LaurieWired/Malimite";
    license = lib.licenses.asl20;
    maintainers = [ ];
    platforms = lib.platforms.linux;
    mainProgram = "malimite";
  };
}
