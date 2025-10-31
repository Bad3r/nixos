#!/usr/bin/env bash
set -euo pipefail

# Batch transformation script for all remaining app modules
# Usage: ./batch-transform.sh [--dry-run]

DRY_RUN_FLAG="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/../../modules/apps"
OUTPUT_DIR="$SCRIPT_DIR/output"

# Modules already converted (pilot)
SKIP_MODULES=(
  "firefox.nix"
  "brave.nix"
  "wget.nix"
  "jq.nix"
  "git.nix"
  "curl.nix"
  "vim.nix"
  "steam.nix"    # Already correct
  "mangohud.nix" # Already correct
  "rip2.nix"     # Already correct
)

# Modules known to need unfree handling
UNFREE_MODULES=(
  "brave.nix" # Already done
  # Add others as discovered
)

mkdir -p "$OUTPUT_DIR"

# Statistics
total=0
success=0
skipped=0
failed=0

echo "=== Batch Module Transformation ==="
echo "Modules directory: $MODULES_DIR"
echo "Mode: ${DRY_RUN_FLAG:-LIVE}"
echo ""

# Function to check if module should be skipped
should_skip() {
  local module="$1"
  for skip in "${SKIP_MODULES[@]}"; do
    if [ "$module" = "$skip" ]; then
      return 0
    fi
  done
  return 1
}

# Function to determine category
get_category() {
  local module_path="$1"

  # Check if already has proper structure
  if grep -q "options\.programs\..*\.extended" "$module_path" 2>/dev/null; then
    echo "skip"
    return
  fi

  # Check for unfree
  if grep -q "allowedUnfreePackages\|allowUnfreePredicate" "$module_path" 2>/dev/null; then
    echo "unfree"
    return
  fi

  # Default to simple
  echo "simple"
}

# Process all .nix files
for module_file in "$MODULES_DIR"/*.nix; do
  module_name=$(basename "$module_file")
  total=$((total + 1))

  # Skip if in skip list
  if should_skip "$module_name"; then
    echo "SKIP: $module_name (already processed or correct)"
    skipped=$((skipped + 1))
    continue
  fi

  # Determine category
  category=$(get_category "$module_file")

  if [ "$category" = "skip" ]; then
    echo "SKIP: $module_name (already has proper structure)"
    skipped=$((skipped + 1))
    continue
  fi

  # Transform
  echo -n "Processing $module_name ($category)... "
  if "$SCRIPT_DIR/transform-module.sh" "$module_file" "$category" "$DRY_RUN_FLAG" 2>&1 | grep -q "SUCCESS\|DRY-RUN"; then
    echo "✓"
    success=$((success + 1))
  else
    echo "✗ FAILED"
    failed=$((failed + 1))
    echo "$module_name" >>"$OUTPUT_DIR/failed.txt"
  fi
done

echo ""
echo "=== Transformation Summary ==="
echo "Total modules: $total"
echo "Successful: $success"
echo "Skipped: $skipped"
echo "Failed: $failed"
echo ""

if [ $failed -gt 0 ]; then
  echo "Failed modules saved to: $OUTPUT_DIR/failed.txt"
  echo "Review these manually."
fi

exit 0
