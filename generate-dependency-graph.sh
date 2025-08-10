#!/usr/bin/env bash
# Dependency visualization tool for dendritic pattern
set -euo pipefail

# Enable pipe operators for nix commands
export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"

echo "Generating module dependency graph..."

# Create DOT file for graphviz
DOT_FILE="module-dependencies.dot"

cat > "$DOT_FILE" << 'EOF'
digraph modules {
  rankdir=LR;
  node [shape=box, style=rounded];
  
  // Core namespace hierarchy
  "nixos.base" [color=green, style="rounded,filled", fillcolor=lightgreen];
  "nixos.pc" [color=blue, style="rounded,filled", fillcolor=lightblue];
  "nixos.workstation" [color=purple, style="rounded,filled", fillcolor=plum];
  
  // Namespace dependencies
  "nixos.pc" -> "nixos.base" [label="extends"];
  "nixos.workstation" -> "nixos.pc" [label="extends"];
  
  // Module directories
  subgraph cluster_0 {
    label="Semantic Directories";
    style=dotted;
    
    "audio/*" [shape=folder];
    "boot/*" [shape=folder];
    "hardware/*" [shape=folder];
    "networking/*" [shape=folder];
    "security/*" [shape=folder];
    "storage/*" [shape=folder];
    "style/*" [shape=folder];
    "virtualization/*" [shape=folder];
    "window-manager/*" [shape=folder];
  }
  
  // Directory to namespace mappings
  "boot/*" -> "nixos.base" [style=dashed, label="extends"];
  "storage/*" -> "nixos.base" [style=dashed, label="extends"];
  
  "audio/*" -> "nixos.pc" [style=dashed, label="extends"];
  "style/*" -> "nixos.pc" [style=dashed, label="extends"];
  "window-manager/*" -> "nixos.pc" [style=dashed, label="extends"];
  
  "security/*" -> "nixos.workstation" [style=dashed, label="extends"];
  "virtualization/*" -> "nixos.workstation" [style=dashed, label="extends"];
  
  // Named modules (optional)
  "nixos.nvidia-gpu" [color=orange, style="rounded,dashed"];
  "nixos.system76-complete" [color=orange, style="rounded,dashed"];
EOF

# Analyze actual module files and add to graph
echo "  // Actual module analysis" >> "$DOT_FILE"
for file in modules/**/*.nix; do
  [ -f "$file" ] || continue
  
  MODULE=$(basename "$file" .nix)
  DIR=$(basename $(dirname "$file"))
  
  # Skip meta and infrastructure modules
  if [[ "$DIR" == "meta" || "$DIR" == "configurations" || "$DIR" == "hosts" ]]; then
    continue
  fi
  
  # Find what namespace it extends
  if grep -q "flake.modules.nixos.base" "$file" 2>/dev/null; then
    echo "  \"$MODULE\" -> \"nixos.base\" [color=green];" >> "$DOT_FILE"
  fi
  
  if grep -q "flake.modules.nixos.pc" "$file" 2>/dev/null; then
    echo "  \"$MODULE\" -> \"nixos.pc\" [color=blue];" >> "$DOT_FILE"
  fi
  
  if grep -q "flake.modules.nixos.workstation" "$file" 2>/dev/null; then
    echo "  \"$MODULE\" -> \"nixos.workstation\" [color=purple];" >> "$DOT_FILE"
  fi
done

echo "}" >> "$DOT_FILE"

# Generate visualization if graphviz is available
if command -v dot >/dev/null 2>&1; then
  dot -Tpng "$DOT_FILE" -o module-dependencies.png
  dot -Tsvg "$DOT_FILE" -o module-dependencies.svg
  echo "✓ Dependency graph generated:"
  echo "  - module-dependencies.png"
  echo "  - module-dependencies.svg"
  echo "  - module-dependencies.dot"
else
  echo "Install graphviz to generate visual graphs:"
  echo "  nix-shell -p graphviz --run \"dot -Tpng $DOT_FILE -o module-dependencies.png\""
  echo ""
  echo "DOT file saved as: $DOT_FILE"
fi

# Generate text summary
echo ""
echo "=== Module Namespace Summary ==="
echo ""
echo "Modules extending nixos.base:"
grep -l "flake.modules.nixos.base" modules/**/*.nix 2>/dev/null | while read -r f; do
  echo "  - $(basename "$f" .nix)"
done | sort -u

echo ""
echo "Modules extending nixos.pc:"
grep -l "flake.modules.nixos.pc" modules/**/*.nix 2>/dev/null | while read -r f; do
  echo "  - $(basename "$f" .nix)"
done | sort -u

echo ""
echo "Modules extending nixos.workstation:"
grep -l "flake.modules.nixos.workstation" modules/**/*.nix 2>/dev/null | while read -r f; do
  echo "  - $(basename "$f" .nix)"
done | sort -u

echo ""
echo "✓ Dependency analysis complete"