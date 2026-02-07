{
  lib,
  writeShellApplication,
  fd,
  ffmpeg,
  parallel,
  coreutils,
  gawk,
  gnugrep,
}:

writeShellApplication {
  name = "video-cache";

  runtimeInputs = [
    fd
    ffmpeg # provides ffprobe
    parallel
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
    VIDEO_DIR=""

    # Argument parsing
    while [[ $# -gt 0 ]]; do
      case $1 in
        --force) FORCE=true; shift ;;
        --quiet) QUIET=true; shift ;;
        -*)
          echo -e "''${RED}Unknown option: $1''${NC}" >&2
          exit 1
          ;;
        *)
          VIDEO_DIR="$1"
          shift
          ;;
      esac
    done

    # Fallback chain: arg > $VID_DIR > $PWD
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
      tmp_file=$(mktemp)
      while IFS=$'\t' read -r duration filepath; do
        if [[ -f "$filepath" ]]; then
          printf '%s\t%s\n' "$duration" "$filepath" >> "$tmp_file"
        else
          ((removed++)) || true
        fi
      done < "$CACHE_FILE"
      mv "$tmp_file" "$CACHE_FILE"
    fi

    # Find new files (not in cache)
    new_files=$(fd -t f '\.(3gp|avi|flv|m4v|mkv|mov|mp4|mpg|webm|wmv)$' -i "$VIDEO_DIR" \
      | grep -Fxvf <(cut -f2 "$CACHE_FILE") || true)

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

    # Sort cache by filepath (alphabetical)
    if [[ -s "$CACHE_FILE" ]]; then
      sort -t$'\t' -k2 -o "$CACHE_FILE" "$CACHE_FILE"
    fi

    # Calculate totals
    total=$(wc -l < "$CACHE_FILE")
    skipped=$((total - added))

    # Summary output
    if [[ "$QUIET" != true ]]; then
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
    fi
  '';

  meta = {
    description = "Build and maintain a cache of video file durations";
    homepage = "https://github.com/vx/nixos";
    license = lib.licenses.mit;
    mainProgram = "video-cache";
    platforms = lib.platforms.linux;
  };
}
