{
  lib,
  runCommand,
  gnutar,
  zstd,
  fontconfig,
  findutils,
  gnugrep,
  python3,
  pname,
  version,
  archives,
  fontRoot,
  requiredFamilies,
  checkManifest ? false,
  documentation ? [ ],
  license ? lib.licenses.unfree,
  fontWeights ? { },
}:
let
  fixWeights = builtins.toFile "fix-font-weights.py" ''
    import io
    import json
    import pathlib
    import struct
    import sys
    from fontTools.ttLib.sfnt import SFNTReader, SFNTWriter

    for name, weight in json.loads(sys.argv[1]).items():
        path = pathlib.Path(sys.argv[2]) / name
        with io.BytesIO(path.read_bytes()) as source, io.BytesIO() as output:
            reader = SFNTReader(source)
            writer = SFNTWriter(output, len(reader.tables), sfntVersion=reader.sfntVersion)
            # Preserve other tables as raw bytes rather than recompiling them.
            for tag in reader.keys():
                data = reader[tag]
                if tag == "OS/2":
                    data = data[:4] + struct.pack(">H", weight) + data[6:]
                writer[tag] = data
            writer.close()
            path.write_bytes(output.getvalue())
  '';
in
runCommand "${pname}-${version}"
  {
    inherit pname version;
    nativeBuildInputs = [
      gnutar
      zstd
      fontconfig
      findutils
      gnugrep
    ];
    meta = {
      description = "${pname} fonts from the private asset repository";
      inherit license;
      platforms = lib.platforms.all;
    };
  }
  ''
    set -euo pipefail
    cat ${lib.escapeShellArgs (map (archive: "${archive}") archives)} | tar -I zstd -xf -
    ${lib.optionalString checkManifest "sha256sum --check --strict SHA256SUMS"}
    fontRoot=${lib.escapeShellArg fontRoot}
    test -d "$fontRoot"
    families="$(find "$fontRoot" -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \) -exec fc-query -f '%{[]family{%{family}\n}}' {} +)"
    for wanted in ${lib.escapeShellArgs requiredFamilies}; do
      if ! grep -Fxq -- "$wanted" <<<"$families"; then
        echo "${pname} archive has no face declaring $wanted" >&2
        exit 1
      fi
    done
    find "$fontRoot" -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \) -print0 |
      while IFS= read -r -d "" font; do
        install -Dm0644 "$font" "$out/share/fonts/truetype/${pname}/''${font#"$fontRoot/"}"
      done
    ${lib.optionalString (fontWeights != { }) ''
      ${
        python3.withPackages (p: [ p.fonttools ])
      }/bin/python ${fixWeights} ${lib.escapeShellArg (builtins.toJSON fontWeights)} "$out/share/fonts/truetype/${pname}"
    ''}
    ${lib.optionalString (documentation != [ ]) ''
      mkdir -p "$out/share/doc/${pname}"
      cp -R ${lib.escapeShellArgs documentation} "$out/share/doc/${pname}/"
    ''}
  ''
