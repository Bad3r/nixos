{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  zlib,
  versionCheckHook,
  callPackage,
}:

let
  pin = lib.importJSON ./hashes.json;
  archives = lib.mapAttrs (_: archive: fetchurl { inherit (archive) url hash; }) (
    pin.archives // pin.runtime
  );
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ddisasm";
  inherit (pin) version;
  src = archives.ddisasm;

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    zlib
  ];
  strictDeps = true;
  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/lib/ddisasm" "$out/share/doc/ddisasm/vendor"
    ${lib.concatMapStringsSep "\n" (name: ''
      unpackDir=$(mktemp -d)
      dpkg-deb --extract ${archives.${name}} "$unpackDir"
      if [ -f "$unpackDir/usr/bin/ddisasm" ]; then
        install -m755 "$unpackDir/usr/bin/ddisasm" "$out/bin/ddisasm"
      fi
      if [ -d "$unpackDir/usr/lib" ]; then
        while IFS= read -r -d "" library; do
          target="$out/lib/ddisasm/$(basename "$library")"
          if [ -e "$target" ] || [ -L "$target" ]; then
            echo "Duplicate bundled library: $target" >&2
            exit 1
          fi
          cp -P "$library" "$target"
        done < <(find "$unpackDir/usr/lib" -name '*.so*' \( -type f -o -type l \) -print0)
      fi
      if [ -d "$unpackDir/usr/share/doc" ]; then
        cp -r "$unpackDir/usr/share/doc" "$out/share/doc/ddisasm/vendor/${name}"
      fi
    '') (builtins.attrNames archives)}
    test -x "$out/bin/ddisasm"
    runHook postInstall
  '';

  preFixup = ''
    addAutoPatchelfSearchPath "$out/lib/ddisasm"
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru = {
    updateScript = ./update.py;
    tests.roundtrip = callPackage ./test.nix { ddisasm = finalAttrs.finalPackage; };
  };

  meta = {
    description = "Datalog disassembler producing reassemblable assembly and GTIRB";
    homepage = "https://github.com/GrammaTech/ddisasm";
    license = lib.licenses.agpl3Only;
    mainProgram = "ddisasm";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
