#!/usr/bin/env bash
# Description: Minifies Nix configuration files in a specified directory.
#              It removes comments, unnecessary whitespace, and concatenates
#              each .nix file's content onto a single line, prefixed by a
#              header indicating the original file path.
#              The 'hardware-configuration.nix' file is ignored.
#              The final combined output is copied to the clipboard if 'xclip'
#              or 'pbcopy' is available, and also printed to standard output.
# Usage: ./minify_nix_config.sh $PWD
# NOTE: Uses non-POSIX features: 'pipefail', 'find -print0', 'xargs -0' for robustness.
# Author: github.com/Bad3r 
# Email: bad3r @ unsigned .sh
# License: AGPL-3.0-or-later
# Version: 1.0.0

set -euo pipefail
IFS=$(printf '\n\t')

dir=${1:-}

# --- Start: Argument and Directory Checks ---
if [ -z "$dir" ]; then
    printf "Usage: %s <directory>\n" "$0" >&2
    exit 1
fi
if [ ! -d "$dir" ]; then
    printf "Error: %s is not a directory.\n" "$dir" >&2
    exit 1
fi
# Check if any processable .nix files exist
# NOTE: 'find -print0', 'xargs -0', and find's '!' are non-POSIX extensions.
if ! find "$dir" -type f -name '*.nix' ! -name 'hardware-configuration.nix' -print -quit | grep -q .; then
    printf "No processable .nix files found in specified directory (excluding hardware-configuration.nix).\n" >&2
    exit 0
fi
# --- End: Argument and Directory Checks ---

# Awk script to process files
# shellcheck disable=SC2016
awk_script='
function flush_buffer() {
  if (current_filename != "") {
    printf "# %s\n", current_filename
    sub(/^[[:space:]]+/, "", current_file_content)
    sub(/[[:space:]]+$/, "", current_file_content)
    gsub(/;[[:space:]]+/, ";", current_file_content)
    print current_file_content
    current_file_content = ""
    current_filename = ""
    output_started = 1
  }
}

FNR==1 {
  if (NR > 1) {
    flush_buffer()
  }
  rel = FILENAME
  sub(base "/", "", rel)
  current_filename = rel
}

/^[[:space:]]*#/ { next } # Skip full comment lines

{
  sub(/#.*/, "") # Remove inline comments
  sub(/^[[:space:]]+/, "") # Remove leading space
  sub(/[[:space:]]+$/, "") # Remove trailing space

  if ($0 != "") {
    if (current_file_content != "") {
       current_file_content = current_file_content " " $0
    } else {
       current_file_content = $0
    }
  }
}

END {
  flush_buffer()
}
'

# Execute find (excluding hardware-configuration.nix) and awk
minified_content=$(find "$dir" -type f -name '*.nix' ! -name 'hardware-configuration.nix' -print0 |
    xargs -0 awk -v base="$dir" "$awk_script")

# --- Clipboard/Output logic ---
if command -v xclip &>/dev/null; then
    printf '%s' "$minified_content" | xclip -selection clipboard
    printf "Minified content copied to clipboard.\n" >&2
elif command -v pbcopy &>/dev/null; then
    printf '%s' "$minified_content" | pbcopy
    printf "Minified content copied to clipboard.\n" >&2
else
    printf "No clipboard utility found. Outputting to stdout:\n" >&2
fi

# Print the final minified content to stdout
printf '%s' "$minified_content"

# Add a newline to stderr for clean prompt
printf "\n" >&2
# --- End Clipboard/Output logic ---
