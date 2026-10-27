{
  lib,
  runCommand,
  gnutar,
  zstd,
  fontconfig,
  findutils,
  gnugrep,
  pname,
  version,
  archives,
  fontRoot,
  requiredFamilies,
  checkManifest ? false,
  documentation ? [ ],
  license ? lib.licenses.unfree,
}:
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
    ${lib.optionalString (documentation != [ ]) ''
      mkdir -p "$out/share/doc/${pname}"
      cp -R ${lib.escapeShellArgs documentation} "$out/share/doc/${pname}/"
    ''}
  ''
