{
  lib,
  writeShellApplication,
  fd,
  ffmpeg,
  mpv,
  coreutils,
  gawk,
  gnugrep,
}:

writeShellApplication {
  name = "video-cache";

  runtimeInputs = [
    fd
    ffmpeg # provides ffprobe
    mpv
    coreutils
    gawk
    gnugrep
  ];

  text = /* bash */ ''
    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'

    # Defaults
    FORCE=false
    QUIET=false
    SHUFFLE=false
    VIDEO_DIR=""
    MIN=""
    MAX=""

    parse_duration() {
      local val="$1"
      if [[ "$val" =~ ^([0-9]+)([smh]?)$ ]]; then
        local n="''${BASH_REMATCH[1]}"
        local unit="''${BASH_REMATCH[2]}"
        case "$unit" in
          h) echo $(( n * 3600 )) ;;
          m) echo $(( n * 60 )) ;;
          s|"") echo "$n" ;;
        esac
      else
        echo -e "''${RED}Error: invalid duration '$val' (expected N, Ns, Nm, or Nh)''${NC}" >&2
        exit 1
      fi
    }

    parse_range() {
      local val="$1"
      if [[ "$val" == *:* ]]; then
        local left="''${val%%:*}"
        local right="''${val#*:}"
        if [[ -n "$left" ]]; then
          MIN=$(parse_duration "$left")
        fi
        if [[ -n "$right" ]]; then
          MAX=$(parse_duration "$right")
        fi
      else
        MIN=$(parse_duration "$val")
      fi
    }

    # Argument parsing
    while [[ $# -gt 0 ]]; do
      case $1 in
        -h|--help)
          echo 'Usage: video-cache [OPTIONS]'
          echo
          echo 'Options:'
          echo "  -p, --path DIR        Video directory (default: \$VID_DIR or \$PWD)"
          echo '  -s, --shuffle         Play in shuffled order'
          echo '  -d, --duration RANGE  Filter by duration (inclusive bounds)'
          echo '  -f, --force           Rebuild cache from scratch'
          echo '  -q, --quiet           Suppress summary output'
          echo '  -h, --help            Show this help'
          echo
          echo 'RANGE syntax:  MIN[:MAX]   between MIN and MAX (both inclusive)'
          echo '               MIN         same as MIN:    (lower bound only)'
          echo '               :MAX        upper bound only'
          echo 'DUR inside RANGE: N | Ns | Nm | Nh  (e.g., 60s, 3m, 1h).'
          echo
          echo 'Order: depth-first tree order. Within a directory, entries sort'
          echo 'case-insensitively with natural numbers (ep2 before ep10), and'
          echo 'each directory keeps its contents contiguous. Use -s to randomize.'
          echo
          echo 'Examples:'
          echo '  video-cache -d 3m          play videos >= 3 min'
          echo '  video-cache -d :30s        play videos <= 30 seconds'
          echo '  video-cache -d 3m:10m      play videos between 3 and 10 minutes'
          echo '  video-cache -s             play all, shuffled'
          echo
          echo 'Updates the cache and plays matching videos with mpv.'
          exit 0
          ;;
        -p|--path)
          VIDEO_DIR="$2"
          shift 2
          ;;
        -s|--shuffle) SHUFFLE=true; shift ;;
        -d|--duration)
          parse_range "$2"
          shift 2
          ;;
        -f|--force) FORCE=true; shift ;;
        -q|--quiet) QUIET=true; shift ;;
        *)
          echo -e "''${RED}Unknown argument: $1''${NC}" >&2
          exit 1
          ;;
      esac
    done

    # Fallback chain: --path > $VID_DIR > $PWD
    VIDEO_DIR="''${VIDEO_DIR:-''${VID_DIR:-$PWD}}"

    # Validate directory
    if [[ ! -d "$VIDEO_DIR" ]]; then
      echo -e "''${RED}Error: Directory does not exist: $VIDEO_DIR''${NC}" >&2
      exit 1
    fi

    # Cache setup
    CACHE_DIR="$VIDEO_DIR/.cache"
    CACHE_FILE="$CACHE_DIR/video-durations.tsv"
    ERROR_LOG="$CACHE_DIR/video-errors.log"

    mkdir -p "$CACHE_DIR"
    touch "$CACHE_FILE"

    # Force mode: clear cache and error log
    if [[ "$FORCE" == true ]]; then
      : > "$CACHE_FILE"
      : > "$ERROR_LOG"
    fi

    # Remove deleted files from cache
    removed=0
    if [[ -s "$CACHE_FILE" ]]; then
      tmp_file=$(mktemp "$CACHE_DIR/.video-durations.XXXXXX")
      trap 'rm -f -- "$tmp_file"' EXIT
      chmod --reference="$CACHE_FILE" -- "$tmp_file"
      # Preserve the opaque record after its first delimiter so literal tabs
      # in the filepath survive pruning without reformatting the duration.
      while IFS= read -r record; do
        if [[ "$record" != *$'\t'* ]]; then
          ((removed++)) || true
          continue
        fi
        filepath="''${record#*$'\t'}"
        if [[ -f "$filepath" ]]; then
          printf '%s\n' "$record" >> "$tmp_file"
        else
          ((removed++)) || true
        fi
      done < "$CACHE_FILE"
      mv -- "$tmp_file" "$CACHE_FILE"
      trap - EXIT
    fi

    # Find new files (not in cache)
    new_files=$(fd -t f '\.(3gp|avi|flv|m4v|mkv|mov|mp4|mpg|webm|wmv)$' -i "$VIDEO_DIR" \
      | LC_ALL=C grep -Fxvf <(
        LC_ALL=C awk -F'\t' 'index($0, "\t") { print substr($0, index($0, "\t") + 1) }' "$CACHE_FILE"
      ) || true)

    added=0
    failed=0

    if [[ -n "$new_files" ]]; then
      total_new=$(echo "$new_files" | wc -l)

      if [[ "$QUIET" != true ]]; then
        echo -e "''${BLUE}Processing $total_new new video(s)...''${NC}"
      fi

      # Clear error log for this run (append mode for parallel)
      : > "$ERROR_LOG"

      # Process videos in parallel
      while IFS= read -r file; do
        duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file" 2>/dev/null || true)

        if [[ -n "$duration" ]]; then
          printf '%s\t%s\n' "$duration" "$file" >> "$CACHE_FILE"
          ((added++)) || true
        else
          echo "$file" >> "$ERROR_LOG"
          if [[ "$QUIET" != true ]]; then
            echo -e "''${RED}Failed: $file''${NC}" >&2
          fi
          ((failed++)) || true
        fi

        if [[ "$QUIET" != true ]]; then
          processed=$((added + failed))
          pct=$((processed * 100 / total_new))
          printf "\r''${BLUE}Progress: [%-50s] %d%%''${NC}" "$(printf '#%.0s' $(seq 1 $((pct / 2))))" "$pct" >&2
        fi
      done <<< "$new_files"

      if [[ "$QUIET" != true ]]; then
        echo "" >&2
      fi
    fi

    # Tree order: / becomes \001 so a directory's contents stay contiguous and
    # precede a same-named sibling. The transient key encodes each significant
    # digit as one zero followed by a NUL terminator, so natural order has no
    # fixed digit-run ceiling. Literal tabs use \002 in the key; the original
    # cache record remains opaque after its duration field.
    if [[ -s "$CACHE_FILE" ]]; then
      sort_tmp=$(mktemp "$CACHE_DIR/.video-durations.XXXXXX")
      trap 'rm -f -- "$sort_tmp"' EXIT
      chmod --reference="$CACHE_FILE" -- "$sort_tmp"
      LC_ALL=C awk -F'\t' '
        function natnum(n,   out, i) {
          sub(/^0+/, "", n)
          if (n == "") { n = "0" }
          out = ""
          for (i = 1; i <= length(n); i++) { out = out "0" }
          return out "\000" n
        }
        function treekey(p,   out, pre, num) {
          p = tolower(p)
          gsub(/\t/, "\002", p)
          gsub(/\//, "\001", p)
          out = ""
          while (match(p, /[0-9]+/)) {
            pre = substr(p, 1, RSTART - 1)
            num = substr(p, RSTART, RLENGTH)
            out = out pre natnum(num)
            p = substr(p, RSTART + RLENGTH)
          }
          return out p
        }
        BEGIN { OFS = "\t" }
        {
          record = $0
          path = substr(record, index(record, "\t") + 1)
          print treekey(path), record
        }
      ' "$CACHE_FILE" \
        | LC_ALL=C sort -t$'\t' -k1,1 -k3 \
        | cut -f2- >"$sort_tmp"
      mv -- "$sort_tmp" "$CACHE_FILE"
      trap - EXIT
    fi

    # Calculate totals
    total=$(wc -l < "$CACHE_FILE")
    skipped=$((total - added))

    # Summary output (stderr so stdout stays clean for pipelines)
    if [[ "$QUIET" != true ]]; then
      {
        echo ""
        echo -e "''${BOLD}═══════════════════════════════════════''${NC}"
        echo -e "''${BOLD}         Video Cache Summary''${NC}"
        echo -e "''${BOLD}═══════════════════════════════════════''${NC}"
        echo -e "''${GREEN}  Added:''${NC}   $added"
        echo -e "''${BLUE}  Skipped:''${NC} $skipped"
        echo -e "''${RED}  Removed:''${NC} $removed"
        echo -e "''${RED}  Failed:''${NC}  $failed"
        echo -e "''${BOLD}  ─────────────────────────────────────''${NC}"
        echo -e "''${BOLD}  Total:''${NC}   $total"
        echo -e "''${BOLD}═══════════════════════════════════════''${NC}"
      } >&2
    fi

    # Play matching videos with mpv (bounds are inclusive)
    mapfile -t videos < <(LC_ALL=C awk -F'\t' \
      -v min="$MIN" -v max="$MAX" '
        {
          path = substr($0, index($0, "\t") + 1)
          if ((min == "" || ($1+0) >= (min+0)) &&
              (max == "" || ($1+0) <= (max+0))) { print path }
        }
      ' "$CACHE_FILE")
    if [[ "''${#videos[@]}" -eq 0 ]]; then
      echo -e "''${RED}No videos matched.''${NC}" >&2
      exit 1
    fi
    if [[ "$SHUFFLE" == true ]]; then
      exec mpv --shuffle -- "''${videos[@]}"
    else
      exec mpv -- "''${videos[@]}"
    fi
  '';

  meta = {
    description = "Build and maintain a cache of video file durations";
    homepage = "https://github.com/Bad3r/nixos";
    license = lib.licenses.mit;
    mainProgram = "video-cache";
    platforms = lib.platforms.linux;
  };
}
