{
  pkgs,
  lib,
  moduleDocsJson,
  moduleDocsMarkdown,
}:
let
  formats = {
    json = "${moduleDocsJson}/share/module-docs";
    md = "${moduleDocsMarkdown}/share/module-docs";
  };
  formatKeys = lib.attrNames formats;
  formatKeysString = lib.concatStringsSep " " formatKeys;
  pathCases = lib.concatStringsSep "\n" (
    map (format: "          ${format}) echo ${formats.${format}} ;;") formatKeys
  );
  script = pkgs.writeShellApplication {
    name = "module-docs-exporter";
    runtimeInputs = with pkgs; [
      coreutils
      rsync
      jq
    ];
    text = ''
            set -euo pipefail
            formats="json,md"
            out_dir=".cache/module-docs"
            print_paths="false"
            while [ $# -gt 0 ]; do
              case "$1" in
                --format)
                  shift
                  [ $# -gt 0 ] || { echo "--format requires argument" >&2; exit 1; }
                  formats="$1"
                  shift
                  ;;
                --out)
                  shift
                  [ $# -gt 0 ] || { echo "--out requires path" >&2; exit 1; }
                  out_dir="$1"
                  shift
                  ;;
                --print-paths)
                  print_paths="true"
                  shift
                  ;;
                --help|-h)
                  cat <<USAGE
      module-docs-exporter --format json,md --out <dir>
        --format       Comma-separated list (${formatKeysString})
        --out          Destination directory (default: .cache/module-docs)
        --print-paths  Print source store paths and exit
      USAGE
                  exit 0
                  ;;
                *)
                  echo "Unknown argument: $1" >&2
                  exit 1
                  ;;
              esac
            done

            formats_list=$(printf "%s" "$formats" | tr ',' ' ')

            validate() {
              local needle="$1"
              for candidate in ${formatKeysString}; do
                if [ "$candidate" = "$needle" ]; then
                  return 0
                fi
              done
              return 1
            }

            for requested in $formats_list; do
              [ -z "$requested" ] && continue
              if ! validate "$requested"; then
                echo "Unsupported format: $requested" >&2
                exit 2
              fi
            done

            emit_paths() {
              for key in ${formatKeysString}; do
                for requested in $formats_list; do
                  if [ "$requested" = "$key" ]; then
                    case "$key" in
      ${pathCases}
                    esac
                  fi
                done
              done
            }

            if [ "$print_paths" = "true" ]; then
              emit_paths
              exit 0
            fi

            mkdir -p "$out_dir"
            for key in ${formatKeysString}; do
              matched="false"
              for requested in $formats_list; do
                if [ "$requested" = "$key" ]; then
                  matched="true"
                  break
                fi
              done
              if [ "$matched" != "true" ]; then
                continue
              fi
              src="$(case "$key" in
      ${pathCases}
              esac)"
              dest="$out_dir/$key"
              rm -rf "$dest"
              mkdir -p "$dest"
              rsync -a "$src/" "$dest/"
            done

            echo "Module docs exported to $out_dir"
    '';
  };
in
script
