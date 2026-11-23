{
  lib,
  python3Packages,
  fetchFromGitHub,
  wrapGAppsHook4,
  gobject-introspection,
  gtk4,
  libadwaita,
  libsoup_3,
  webkitgtk_6_0,
  protobuf_33,
  dex2jar,
  jre,
}:

let
  pin = lib.importJSON ./hashes.json;
in
python3Packages.buildPythonApplication rec {
  pname = "pbtk";
  inherit (pin) version;
  pyproject = true;

  src = fetchFromGitHub {
    owner = "marin-m";
    repo = "pbtk";
    tag = version;
    hash = pin.srcHash;
  };

  # protoc and dex2jar come from nixpkgs; protoc must match the protobuf
  # Python runtime that imports its generated modules, and protobuf 7 drops
  # FieldDescriptor.label, which pbtk still reads. Only the Linux Jad build
  # stays, as nixpkgs has no Jad.
  postPatch = ''
    rm -r src/pbtk/utils/external/protoc src/pbtk/utils/external/dex2jar
    rm src/pbtk/utils/external/jad/jad.exe src/pbtk/utils/external/jad/jad_osx
    substituteInPlace src/pbtk/utils/common.py \
      --replace-fail "# Disable the C++ extension for Python-Protobuf" \
        "protoc = '${lib.getExe' protobuf_33 "protoc"}'
    dex2jar = '${lib.getExe' dex2jar "d2j-dex2jar"}'

    # Disable the C++ extension for Python-Protobuf"
    substituteInPlace pyproject.toml \
      --replace-fail '"pbtk.utils.external.dex2jar" = ["*"]' "" \
      --replace-fail '"pbtk.utils.external.dex2jar.lib" = ["*"]' "" \
      --replace-fail '"pbtk.utils.external.protoc" = ["*"]' ""
  '';

  build-system = [ python3Packages.setuptools ];

  dependencies = [
    python3Packages.protobuf6
    python3Packages.pygobject3
    python3Packages.websocket-client
  ];

  pythonRelaxDeps = [ "protobuf" ];

  nativeBuildInputs = [
    wrapGAppsHook4
    gobject-introspection
  ];

  buildInputs = [
    gtk4
    libadwaita
    libsoup_3
    webkitgtk_6_0
  ];

  dontWrapGApps = true;

  preFixup = ''
    makeWrapperArgs+=(
      "''${gappsWrapperArgs[@]}"
      --prefix PATH : ${lib.makeBinPath [ jre ]}
    )
  '';

  postInstall = ''
    chmod +x $out/${python3Packages.python.sitePackages}/pbtk/utils/external/jad/jad
    install -Dm644 src/pbtk/ui/assets/re.fossplant.pbtk.svg -t $out/share/icons/hicolor/scalable/apps/
    install -Dm644 src/pbtk/ui/assets/re.fossplant.pbtk.desktop -t $out/share/applications/
    install -Dm644 src/pbtk/ui/assets/re.fossplant.pbtk.metainfo.xml -t $out/share/metainfo/
  '';

  meta = {
    description = "Toolset for reverse engineering and fuzzing Protobuf-based apps";
    homepage = "https://github.com/marin-m/pbtk";
    changelog = "https://github.com/marin-m/pbtk/releases/tag/${version}";
    # The bundled Jad decompiler is closed-source freeware.
    license = with lib.licenses; [
      gpl3Plus
      unfree
    ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    mainProgram = "pbtk";
    platforms = [ "x86_64-linux" ];
  };

  passthru.updateScript = ./update.py;
}
