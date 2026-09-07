_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.hook-docs-style = pkgs.writeShellApplication {
        name = "hook-docs-style";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gawk
          pkgs.git
        ];
        text = # bash
          ''
            set -euo pipefail

            root=$(git rev-parse --show-toplevel)
            cd "$root"

            if [ "$#" -eq 0 ]; then
              exit 0
            fi

            pattern_source="docs/technical-writing/banned-phrases.txt"
            violations=0
            tmpdir=$(mktemp -d -t docs-style.XXXXXX)
            trap 'rm -rf "$tmpdir"' EXIT

            grep_status=0

            # Runs grep, records its exit status in grep_status (0 match, 1 no match)
            # and aborts the hook on any other status, a real grep failure.
            run_grep() {
              grep_status=0
              grep "$@" || grep_status=$?
              if [ "$grep_status" -gt 1 ]; then
                echo "docs-style: grep failed (exit $grep_status): grep $*" >&2
                exit "$grep_status"
              fi
              return 0
            }

            trim() {
              local s=$1
              s=''${s#"''${s%%[![:space:]]*}"}
              s=''${s%"''${s##*[![:space:]]}"}
              printf '%s' "$s"
            }

            # Blanks lines inside ``` or ~~~ fences (any indentation); keeps line
            # numbers stable for the -n reports downstream.
            blank_fenced_blocks() {
              awk '
                BEGIN { in_fence = 0; fence_char = "" }
                {
                  stripped = $0
                  sub(/^[ \t]*/, "", stripped)
                  if (in_fence) {
                    print ""
                    if (stripped ~ ("^" fence_char "{3,}[ \t]*$")) { in_fence = 0 }
                    next
                  }
                  if (stripped ~ /^```/) { fence_char = "`"; in_fence = 1; print ""; next }
                  if (stripped ~ /^~~~/) { fence_char = "~"; in_fence = 1; print ""; next }
                  print
                }
              ' "$1" >"$2"
            }

            # Drops backtick-delimited inline code spans, keeping the rest of each
            # line so phrase matches never fire on identifiers inside code spans.
            strip_inline_code() {
              awk '
                {
                  line = $0
                  out = ""
                  in_code = 0
                  len = length(line)
                  for (i = 1; i <= len; i++) {
                    ch = substr(line, i, 1)
                    if (ch == "`") { in_code = !in_code; continue }
                    if (!in_code) out = out ch
                  }
                  print out
                }
              ' "$1" >"$2"
            }

            # Prints "lineno<TAB>target" for every `](target)` occurrence.
            extract_link_targets() {
              awk '
                {
                  line = $0
                  while (match(line, /\]\([^)]*\)/)) {
                    target = substr(line, RSTART + 2, RLENGTH - 3)
                    print NR "\t" target
                    line = substr(line, RSTART + RLENGTH)
                  }
                }
              ' "$1"
            }

            # Prints "lineno<TAB>span" for every backtick-delimited inline code span.
            extract_code_spans() {
              awk '
                {
                  line = $0
                  len = length(line)
                  in_code = 0
                  span = ""
                  for (i = 1; i <= len; i++) {
                    ch = substr(line, i, 1)
                    if (ch == "`") {
                      if (in_code) { print NR "\t" span; span = "" }
                      in_code = !in_code
                      continue
                    }
                    if (in_code) span = span ch
                  }
                }
              ' "$1"
            }

            check_line_cap() {
              local path=$1
              local lines
              lines=$(wc -l <"$path")
              if [ "$lines" -gt 150 ]; then
                echo "$path: $lines lines exceeds the 150 line cap" >&2
                violations=$((violations + 1))
              fi
            }

            check_banned_phrases() {
              local path=$1
              local text=$2
              local hits="$tmpdir/phrase-hits"
              run_grep -E -i -n -f "$tmpdir/patterns" "$text" >"$hits"
              while IFS=: read -r lineno rest; do
                [ -z "$lineno" ] && continue
                echo "$path:$lineno: $(trim "$rest")" >&2
                violations=$((violations + 1))
              done <"$hits"
            }

            # Strips a `<...>` wrapper and a trailing quoted title; a pure anchor
            # must be caught before the fragment is cut, since it starts with #.
            normalize_link_target() {
              local target=$1
              case "$target" in
              "<"*">") target=''${target#<} target=''${target%>} ;;
              esac
              target=''${target%%[[:space:]]\"*}
              target=''${target%%[[:space:]]\'*}
              printf '%s' "$target"
            }

            is_skippable_target() {
              case "$1" in
              http://* | https://* | mailto:* | tel:* | \#*) return 0 ;;
              *) return 1 ;;
              esac
            }

            check_relative_links() {
              local path=$1
              local text=$2
              local dir
              dir=$(dirname "$path")
              local hits="$tmpdir/link-hits"
              extract_link_targets "$text" >"$hits"
              while IFS=$'\t' read -r lineno raw_target; do
                [ -z "$lineno" ] && continue
                local target
                target=$(normalize_link_target "$raw_target")
                if is_skippable_target "$target"; then
                  continue
                fi
                target=''${target%%#*}
                [ -z "$target" ] && continue
                local resolved
                if [ "''${target#/}" != "$target" ]; then
                  resolved="$root$target"
                else
                  resolved="$dir/$target"
                fi
                if [ ! -e "$resolved" ]; then
                  echo "$path:$lineno: relative link target does not resolve: $target" >&2
                  violations=$((violations + 1))
                fi
              done <"$hits"
            }

            has_excluded_chars() {
              run_grep -q -E '[*<>{}$?[:space:]]' <<<"$1"
              [ "$grep_status" -eq 0 ]
            }

            # Skips spans with a glob character, angle brackets, braces, a dollar
            # sign, a question mark, or whitespace: templated prose, not a path.
            check_backticked_paths() {
              local path=$1
              local text=$2
              local hits="$tmpdir/span-hits"
              extract_code_spans "$text" >"$hits"
              while IFS=$'\t' read -r lineno span; do
                [ -z "$lineno" ] && continue
                case "$span" in
                modules/* | docs/* | scripts/* | packages/* | tests/*) ;;
                *) continue ;;
                esac
                if has_excluded_chars "$span"; then
                  continue
                fi
                local target=$span
                target=''${target%:[0-9]*}
                target=''${target%/}
                if [ ! -e "$root/$target" ]; then
                  echo "$path:$lineno: backticked path does not exist: $target" >&2
                  violations=$((violations + 1))
                fi
              done <"$hits"
            }

            check_file() {
              local path=$1
              [ -f "$path" ] || return 0

              check_line_cap "$path"

              local blanked="$tmpdir/blanked"
              local nocode="$tmpdir/nocode"
              blank_fenced_blocks "$path" "$blanked"
              strip_inline_code "$blanked" "$nocode"

              check_banned_phrases "$path" "$nocode"
              check_relative_links "$path" "$blanked"
              check_backticked_paths "$path" "$blanked"
            }

            run_grep -E -v '^[[:space:]]*(#|$)' "$pattern_source" >"$tmpdir/patterns"

            for path in "$@"; do
              check_file "$path"
            done

            if [ "$violations" -gt 0 ]; then
              echo "docs-style: $violations violation(s)" >&2
              exit 1
            fi
            exit 0
          '';
      };
    };
}
