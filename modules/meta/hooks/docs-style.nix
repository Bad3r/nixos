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
            # numbers stable for the -n reports downstream. The closing run
            # must be at least as long as the opening run, so a longer fence
            # can safely wrap a shorter one shown as an example.
            blank_fenced_blocks() {
              awk '
                BEGIN { in_fence = 0; fence_char = ""; fence_len = 0 }
                {
                  stripped = $0
                  sub(/^[ \t]*/, "", stripped)
                  if (in_fence) {
                    print ""
                    if (stripped ~ ("^" fence_char "{" fence_len ",}[ \t]*$")) { in_fence = 0 }
                    next
                  }
                  if (match(stripped, /^`{3,}/)) {
                    fence_char = "`"; fence_len = RLENGTH; in_fence = 1; print ""; next
                  }
                  if (match(stripped, /^~{3,}/)) {
                    fence_char = "~"; fence_len = RLENGTH; in_fence = 1; print ""; next
                  }
                  print
                }
              ' "$1" >"$2"
            }

            # Drops backtick-delimited inline code spans, keeping the rest of each
            # line so phrase matches never fire on identifiers inside code spans.
            # A span opens on a run of backticks and closes only on the next run
            # of the same length (CommonMark); an unmatched run is literal text.
            strip_inline_code() {
              awk '
                {
                  line = $0
                  len = length(line)
                  out = ""
                  i = 1
                  while (i <= len) {
                    ch = substr(line, i, 1)
                    if (ch != "`") { out = out ch; i++; continue }
                    j = i
                    while (j <= len && substr(line, j, 1) == "`") j++
                    runlen = j - i
                    k = j
                    closed = 0
                    while (k <= len) {
                      if (substr(line, k, 1) != "`") { k++; continue }
                      k2 = k
                      while (k2 <= len && substr(line, k2, 1) == "`") k2++
                      if (k2 - k == runlen) { closed = 1; break }
                      k = k2
                    }
                    if (closed) {
                      i = k + runlen
                    } else {
                      out = out substr(line, i, runlen)
                      i = j
                    }
                  }
                  print out
                }
              ' "$1" >"$2"
            }

            # Blanks the target of a `](target)` inline link and of a
            # `[label]: target` reference-style link definition, so a dated or
            # otherwise phrase-matching URL never trips the banned-phrase scan.
            strip_link_targets() {
              awk '
                {
                  line = $0
                  out = ""
                  while (match(line, /\]\([^)]*\)/)) {
                    out = out substr(line, 1, RSTART) ")"
                    line = substr(line, RSTART + RLENGTH)
                  }
                  out = out line
                  if (match(out, /^[ ]{0,3}\[[^]]+\]:[ \t]+/)) {
                    out = substr(out, 1, RLENGTH)
                  }
                  print out
                }
              ' "$1" >"$2"
            }

            # Prints "lineno<TAB>target" for every `](target)` inline link and
            # every `[label]: target` reference-style link definition.
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
                $0 ~ /^[ ]{0,3}\[[^]]+\]:[ \t]+[^ \t]/ {
                  rest = $0
                  sub(/^[ ]{0,3}\[[^]]+\]:[ \t]+/, "", rest)
                  match(rest, /^[^ \t]+/)
                  print NR "\t" substr(rest, RSTART, RLENGTH)
                }
              ' "$1"
            }

            # Prints "lineno<TAB>span" for every backtick-delimited inline code
            # span, matching closing runs to the opening run length like
            # strip_inline_code.
            extract_code_spans() {
              awk '
                {
                  line = $0
                  len = length(line)
                  i = 1
                  while (i <= len) {
                    ch = substr(line, i, 1)
                    if (ch != "`") { i++; continue }
                    j = i
                    while (j <= len && substr(line, j, 1) == "`") j++
                    runlen = j - i
                    k = j
                    closed = 0
                    while (k <= len) {
                      if (substr(line, k, 1) != "`") { k++; continue }
                      k2 = k
                      while (k2 <= len && substr(line, k2, 1) == "`") k2++
                      if (k2 - k == runlen) { closed = 1; break }
                      k = k2
                    }
                    if (closed) {
                      print NR "\t" substr(line, j, k - j)
                      i = k + runlen
                    } else {
                      i = j
                    }
                  }
                }
              ' "$1"
            }

            check_line_cap() {
              local path=$1
              local lines
              # wc -l counts newlines, undercounting a file whose last line
              # has none; awk's NR counts the final unterminated line too.
              lines=$(awk 'END { print NR }' "$path")
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

            # Strips a trailing quoted title, then a `<...>` wrapper. The title
            # must go first: a bracketed target followed by a title does not
            # itself end in `>`, so stripping brackets first would miss it.
            normalize_link_target() {
              local target=$1
              target=''${target%%[[:space:]][\"\']*}
              case "$target" in
              "<"*">") target=''${target#<} target=''${target%>} ;;
              esac
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
              grep -q -E '[*<>{}$?[:space:]]' <<<"$1"
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
                modules/* | docs/* | scripts/* | packages/* | tests/* | lib/* | .github/* | flake.nix | build.sh) ;;
                *) continue ;;
                esac
                if has_excluded_chars "$span"; then
                  continue
                fi
                local target=$span
                target=''${target%%#*}
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

              # docs/index.md is a table of contents that grows with every
              # page; only the line cap is inapplicable to it, so it stays
              # fully checked for banned phrases and link resolution.
              if [ "$path" != "docs/index.md" ]; then
                check_line_cap "$path"
              fi

              local blanked="$tmpdir/blanked"
              local codeless="$tmpdir/codeless"
              local phrase_text="$tmpdir/phrase-text"
              blank_fenced_blocks "$path" "$blanked"
              strip_inline_code "$blanked" "$codeless"
              strip_link_targets "$codeless" "$phrase_text"

              check_banned_phrases "$path" "$phrase_text"
              check_relative_links "$path" "$codeless"
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
