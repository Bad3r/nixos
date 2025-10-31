#!/usr/bin/env bash
set -euo pipefail

# Transform a NixOS application module to use proper option structure
# Usage: transform-module.sh <module-path> <category> [--dry-run]

if [ $# -lt 2 ]; then
  echo "Usage: $0 <module-path> <category> [--dry-run]"
  echo "Categories: simple, unfree, multi-package, skip"
  exit 1
fi

MODULE_PATH="$1"
CATEGORY="$2"
DRY_RUN="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
OUTPUT_DIR="$SCRIPT_DIR/output"

# Helper: Extract leading comment block
extract_documentation() {
  local file="$1"
  awk '/^\/\*/{flag=1} flag{print} /\*\//{if(flag) exit}' "$file"
}

# Helper: Extract package name from pkgs.<name> reference
extract_package_name() {
  local file="$1"
  local pkg_name

  # Try quoted names first: pkgs."name-with-hyphens"
  pkg_name=$(grep -A2 'environment.systemPackages' "$file" | grep -oP 'pkgs\."[^"]+' | head -1 | sed 's/pkgs\."//' || echo "")

  # If not found, try unquoted: pkgs.name
  if [ -z "$pkg_name" ]; then
    pkg_name=$(grep -A2 'environment.systemPackages' "$file" | grep -oP 'pkgs\.\K[a-zA-Z0-9_-]+' | head -1 || echo "")
  fi

  # If still not found, try any pkgs. reference (quoted)
  if [ -z "$pkg_name" ]; then
    pkg_name=$(grep -oP 'pkgs\."[^"]+' "$file" | head -1 | sed 's/pkgs\."//' || echo "")
  fi

  # Last resort: any pkgs. reference (unquoted)
  if [ -z "$pkg_name" ]; then
    pkg_name=$(grep -oP 'pkgs\.\K[a-zA-Z0-9_-]+' "$file" | head -1 || echo "")
  fi

  echo "$pkg_name"
}

# Helper: Extract unfree package names
extract_unfree_packages() {
  local file="$1"
  local pkg_name="$2"

  if grep -q "allowedUnfreePackages" "$file"; then
    # Try to extract from array - look for ["name"]
    local extracted
    extracted=$(grep -oP '(?<=\[")[^"]+(?="\])' "$file" | head -1 || echo "")
    if [ -n "$extracted" ]; then
      echo "[ \"$extracted\" ]"
    else
      echo "[ \"$pkg_name\" ]"
    fi
  else
    # Default to package name
    echo "[ \"$pkg_name\" ]"
  fi
}

# Helper: Convert package-name to PascalCase for module name
to_pascal_case() {
  local name="$1"
  echo "$name" | sed -r 's/(^|-)([a-z])/\U\2/g'
}

# Helper: Validate Nix syntax
validate_syntax() {
  local content="$1"
  echo "$content" | nix-instantiate --parse - >/dev/null 2>&1
}

# Main transformation logic
transform_module() {
  local module_path="$1"
  local category="$2"

  echo "Transforming: $(basename "$module_path") (category: $category)"

  # Skip if already correct
  if [ "$category" = "skip" ]; then
    echo "  SKIP: Already has proper structure"
    return 0
  fi

  # Extract components
  local pkg_name
  pkg_name=$(extract_package_name "$module_path")

  if [ -z "$pkg_name" ]; then
    echo "  ERROR: Could not extract package name"
    return 1
  fi

  local documentation
  documentation=$(extract_documentation "$module_path")

  if [ -z "$documentation" ]; then
    documentation="/*
  Package: $pkg_name
  Description: TODO: Add description
*/"
  fi

  local module_name
  module_name=$(to_pascal_case "$pkg_name")

  # Select template
  local template_file
  case "$category" in
  simple)
    template_file="$TEMPLATE_DIR/simple.nix.template"
    ;;
  unfree)
    template_file="$TEMPLATE_DIR/unfree.nix.template"
    ;;
  multi-package)
    template_file="$TEMPLATE_DIR/multi-package.nix.template"
    ;;
  *)
    echo "  ERROR: Unknown category: $category"
    return 1
    ;;
  esac

  if [ ! -f "$template_file" ]; then
    echo "  ERROR: Template not found: $template_file"
    return 1
  fi

  # Apply substitutions
  local transformed
  transformed=$(cat "$template_file")
  transformed="${transformed//\{PRESERVED_DOCUMENTATION\}/$documentation}"
  transformed="${transformed//\{PACKAGE_NAME\}/$pkg_name}"
  transformed="${transformed//\{MODULE_NAME\}/$module_name}"

  # Handle unfree packages
  if [ "$category" = "unfree" ]; then
    local unfree_names
    unfree_names=$(extract_unfree_packages "$module_path" "$pkg_name")
    transformed="${transformed//\{UNFREE_PACKAGE_NAMES\}/$unfree_names}"
  fi

  # Handle multi-package (default empty for now)
  if [ "$category" = "multi-package" ]; then
    transformed="${transformed//\{DEFAULT_EXTRA_PACKAGES\}/[ ]}"
  fi

  # Remove additional exports placeholder for now
  transformed="${transformed//\{ADDITIONAL_EXPORTS\}/}"

  # Validate syntax
  if ! validate_syntax "$transformed"; then
    echo "  ERROR: Generated invalid Nix syntax"
    echo "  Debugging: Saving to $OUTPUT_DIR/$(basename "$module_path").error"
    mkdir -p "$OUTPUT_DIR"
    echo "$transformed" >"$OUTPUT_DIR/$(basename "$module_path").error"
    return 1
  fi

  # Write output
  local output_path
  if [ "$DRY_RUN" = "--dry-run" ]; then
    output_path="$OUTPUT_DIR/$(basename "$module_path")"
    mkdir -p "$OUTPUT_DIR"
    echo "  DRY-RUN: Would write to $module_path"
    echo "  Preview saved to: $output_path"
  else
    output_path="$module_path"
    echo "  SUCCESS: Transformed $module_path"
  fi

  echo "$transformed" >"$output_path"
  return 0
}

# Execute
transform_module "$MODULE_PATH" "$CATEGORY"
