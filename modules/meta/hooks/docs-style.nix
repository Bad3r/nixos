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

            # Blanks lines inside ``` or ~~~ fences (any indentation, inside a
            # blockquote too); keeps line numbers stable for the -n reports
            # downstream. The closing run must be at least as long as the
            # opening run, so a longer fence can safely wrap a shorter one
            # shown as an example.
            blank_fenced_blocks() {
              awk '
                BEGIN { in_fence = 0; fence_char = ""; fence_len = 0; fence_depth = 0 }
                {
                  stripped = $0
                  sub(/^[ \t]*/, "", stripped)
                  # A fence inside a blockquote carries a > marker on every one
                  # of its lines, so the markers go with the indentation; their
                  # count is the quote depth the fence was opened at.
                  depth = 0
                  while (sub(/^>[ \t]?/, "", stripped)) { sub(/^[ \t]*/, "", stripped); depth++ }
                  # A fenced block is never lazily continued (CommonMark), so a
                  # line below the depth of a quoted fence ends the quote and
                  # the fence with it, and is prose again.
                  if (in_fence && depth < fence_depth) { in_fence = 0 }
                  if (in_fence) {
                    print ""
                    # A close belongs to the depth its opening did: a quoted
                    # fence shown inside a top-level one is content.
                    if (depth == fence_depth && stripped ~ ("^" fence_char "{" fence_len ",}[ \t]*$")) { in_fence = 0 }
                    next
                  }
                  if (match(stripped, /^`{3,}/)) {
                    fence_char = "`"; fence_len = RLENGTH; fence_depth = depth; in_fence = 1; print ""; next
                  }
                  if (match(stripped, /^~{3,}/)) {
                    fence_char = "~"; fence_len = RLENGTH; fence_depth = depth; in_fence = 1; print ""; next
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

            # Blanks the target of a `](target)` inline link, of a
            # `[label]: target` reference-style link definition, of a GFM
            # autolink, and of a bare scheme://... URL in prose, so a dated
            # or otherwise phrase-matching URL never trips the banned-phrase
            # scan wherever it appears. A reference-style label starting
            # with `^` is a footnote definition, not a link reference, and
            # is left alone.
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
                  if (match(out, /^[ ]{0,3}\[[^]^][^]]*\]:[ \t]+/)) {
                    out = substr(out, 1, RLENGTH)
                  }
                  gsub(/<[A-Za-z][A-Za-z0-9+.-]*:[^ \t<>]*>/, "<>", out)
                  gsub(/[A-Za-z][A-Za-z0-9+.-]*:\/\/[^ \t]*/, "", out)
                  print out
                }
              ' "$1" >"$2"
            }

            # Prints "lineno<TAB>target" for every `](target)` inline link and
            # every `[label]: target` reference-style link definition. A
            # label starting with `^` is a footnote definition, not a link
            # reference, and is skipped.
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
                $0 ~ /^[ ]{0,3}\[[^]^][^]]*\]:[ \t]+[^ \t]/ {
                  rest = $0
                  sub(/^[ ]{0,3}\[[^]^][^]]*\]:[ \t]+/, "", rest)
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
              # The matched text has code spans and link destinations removed,
              # so the report prints the source line the number points at, in
              # one pass over the hits and the page rather than a fork and a
              # re-read per hit. The -s guard matters: on an empty hits file
              # NR == FNR would hold for the page and read every line as a hit.
              if [ -s "$hits" ]; then
                awk -F: -v path="$path" '
                  NR == FNR { want[$1 + 0] = 1; next }
                  (FNR in want) {
                    line = $0
                    sub(/^[[:space:]]+/, "", line)
                    sub(/[[:space:]]+$/, "", line)
                    print path ":" FNR ": " line
                  }
                ' "$hits" "$path" >&2
                violations=$((violations + $(wc -l <"$hits")))
              fi
            }

            # Trims the padding CommonMark allows inside the parentheses, strips
            # a trailing quoted title, then a `<...>` wrapper. The title must go
            # before the wrapper: a bracketed target followed by a title does not
            # itself end in `>`, so stripping brackets first would miss it.
            normalize_link_target() {
              local target
              target=$(trim "$1")
              target=''${target%%[[:space:]][\"\']*}
              case "$target" in
              "<"*">") target=''${target#<} target=''${target%>} ;;
              esac
              printf '%s' "$target"
            }

            # RFC 3986 section 4.2: a leading path segment holding a colon reads
            # as a scheme, so no relative reference starts with `<scheme>:`;
            # the section 3.1 grammar covers every scheme without a list.
            is_skippable_target() {
              case "$1" in
              //* | \#*) return 0 ;;
              esac
              [[ $1 =~ ^[A-Za-z][A-Za-z0-9+.-]*: ]]
            }

            # pre-commit stashes unstaged changes to tracked files only, so an
            # untracked target is still on disk while the hook runs and only
            # the index agrees with the commit. The index cannot change during
            # the run, so it is read once rather than queried per target, which
            # forked git 135 times on docs/index.md alone. Each ancestor
            # directory is recorded too, since a directory is tracked when a
            # file under it is, and the root as `.` for the same reason.
            #
            # Deferred to the first resolution: a run whose arguments are all
            # exempt, or all argument reports, never reaches is_tracked, and
            # expanding every tracked path is the hook's largest fixed cost.
            declare -A tracked_paths=()
            index_read=0
            read_index() {
              [ "$index_read" -eq 0 ] || return 0
              index_read=1
              local entry
              if ! git ls-files -z >"$tmpdir/index"; then
                echo "docs-style: git ls-files failed" >&2
                exit 2
              fi
              while IFS= read -r -d "" entry; do
                while [ -n "$entry" ]; do
                  tracked_paths["$entry"]=1
                  [ "''${entry%/*}" != "$entry" ] || break
                  entry=''${entry%/*}
                done
              done <"$tmpdir/index"
              [ "''${#tracked_paths[@]}" -eq 0 ] || tracked_paths["."]=1
            }

            # Every key in tracked_paths is a clean git-relative path (no . or
            # .. component), so a raw spelling that hits the set is a genuine
            # hit; anything else, including an unclean or unprefixed spelling,
            # falls through to today's realpath call unchanged. -s keeps a
            # symlinked component as written.
            is_tracked() {
              read_index
              local rel=''${1#"$root/"}
              # An empty rel means $1 was exactly "$root/" (the root link
              # target normalizes to this): tracked_paths has no "" key, and
              # bash treats that subscript itself as an error under set -e,
              # so it is never attempted.
              if [ -n "$rel" ] && [ -n "''${tracked_paths["$rel"]:-}" ]; then
                return 0
              fi
              rel=$(realpath -ms --relative-to="$root" -- "$1")
              [ -n "''${tracked_paths["$rel"]:-}" ]
            }

            # Distinguishes a target that is on disk but unstaged from one that
            # is absent, since the fix differs: git add versus a wrong path. A
            # target that climbs outside the tree can never be tracked, so it
            # is named separately instead of pointing at a git add that cannot
            # work.
            report_unresolved() {
              local path=$1 lineno=$2 what=$3 absent=$4 resolved=$5 target=$6
              case "$(realpath -ms --relative-to="$root" -- "$resolved")" in
              .. | ../*)
                echo "$path:$lineno: $what is outside the repository: $target" >&2
                ;;
              *)
                if [ -e "$resolved" ]; then
                  echo "$path:$lineno: $what is not tracked by git: $target" >&2
                else
                  echo "$path:$lineno: $what $absent: $target" >&2
                fi
                ;;
              esac
              violations=$((violations + 1))
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
                if ! is_tracked "$resolved"; then
                  report_unresolved "$path" "$lineno" "relative link target" "does not resolve" "$resolved" "$target"
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
                # The suffixes come off before the match, since flake.nix and
                # build.sh are exact arms that `flake.nix#nixConfig` or a
                # `build.sh:42:5` location would otherwise slip past; the
                # trailing slash comes off after it so `docs/` still meets docs/*.
                local target=$span
                target=''${target%%#*}
                target=''${target%%:[0-9]*}
                case "$target" in
                modules/* | docs/* | scripts/* | packages/* | tests/* | lib/* | .github/* | flake.nix | build.sh) ;;
                *) continue ;;
                esac
                if has_excluded_chars "$target"; then
                  continue
                fi
                target=''${target%/}
                if ! is_tracked "$root/$target"; then
                  report_unresolved "$path" "$lineno" "backticked path" "does not exist" "$root/$target" "$target"
                fi
              done <"$hits"
            }

            # The root README.md is generated by modules/readme.nix; the mirrored
            # manual, drafts, test fixtures and agent instruction files are not
            # pages. Matched here rather than in a pre-commit exclude so
            # tests/docs-style pins the anchors (the docs/ READMEs and
            # docs/claude-code/writing-CLAUDE.md are pages) and so a hand run
            # skips the same paths.
            is_exempt() {
              case "$1" in
              README.md | docs/drafts/* | docs/nixos-manual/* | tests/* | CLAUDE.md | AGENTS.md | */CLAUDE.md | */AGENTS.md) return 0 ;;
              esac
              return 1
            }

            check_file() {
              local path
              # realpath rejects the empty string outright, and under set -e
              # that kills the run with realpath's own message and no
              # violation count; named here like the two argument reports
              # below.
              if [ -z "$1" ]; then
                echo "docs-style: empty path argument" >&2
                violations=$((violations + 1))
                return 0
              fi
              # ./docs/x.md, docs/./x.md and an absolute path all open the same
              # file after the cd above; is_exempt and the index cap skip match
              # the root-relative spelling, so every argument is reduced to it.
              path=$(realpath -ms --relative-to="$root" -- "$1")
              # An argument outside the tree normalizes to a ../ chain that -f
              # still satisfies, and is then checked against the wrong root:
              # every relative link in it resolves under ../, where nothing is
              # tracked. Named as the one problem it is instead.
              case "$path" in
              .. | ../*)
                echo "docs-style: outside the repository: $1" >&2
                violations=$((violations + 1))
                return 0
                ;;
              esac
              # The cd above makes every argument root-relative, so a path typed
              # from a subdirectory, or a typo, would otherwise check nothing
              # and pass. Checked before the exemption so a typo under tests/
              # is loud too.
              if [ ! -f "$path" ]; then
                echo "docs-style: not a file: $path" >&2
                violations=$((violations + 1))
                return 0
              fi
              if is_exempt "$path"; then
                return 0
              fi

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
