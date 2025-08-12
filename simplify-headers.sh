#!/usr/bin/env bash
# Script to simplify module headers to match golden standard minimalist style

set -euo pipefail

echo "=== Simplifying Module Headers to Golden Standard Style ==="
echo ""

# Backup first
backup_dir="modules.backup.simplify.$(date +%Y%m%d-%H%M%S)"
echo "Creating backup at: $backup_dir"
cp -r modules/ "$backup_dir/"

count=0
simplified=0

# Process all .nix files
while IFS= read -r -d '' file; do
    count=$((count + 1))
    
    # Extract the first line to check if it has a multi-line header
    first_line=$(head -1 "$file" 2>/dev/null || echo "")
    
    if [[ "$first_line" =~ ^#.*Module: ]]; then
        # This has our verbose header, simplify it
        filename=$(basename "$file" .nix)
        
        # Extract purpose from existing header if possible
        purpose_line=$(grep "^# Purpose:" "$file" 2>/dev/null | head -1 || echo "")
        if [ -n "$purpose_line" ]; then
            # Extract just the purpose text
            purpose=$(echo "$purpose_line" | sed 's/^# Purpose: //')
            # Make it more concise
            purpose=$(echo "$purpose" | sed 's/ configuration$//' | sed 's/ configuration for .*//')
        else
            # Generate simple purpose from filename
            purpose=$(echo "$filename" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')
        fi
        
        # Find where the actual code starts (first non-comment, non-empty line)
        code_start_line=$(grep -n "^[^#]" "$file" 2>/dev/null | head -1 | cut -d: -f1 || echo "1")
        
        # Create new file with simplified header
        {
            echo "# $filename.nix - $purpose"
            echo ""
            tail -n +$code_start_line "$file"
        } > "$file.tmp"
        
        mv "$file.tmp" "$file"
        echo "Simplified: $file"
        simplified=$((simplified + 1))
    fi
done < <(find modules -name "*.nix" -print0)

echo ""
echo "=== Summary ==="
echo "Total modules processed: $count"
echo "Headers simplified: $simplified"
echo "Backup saved at: $backup_dir"
echo ""
echo "✅ Headers simplified to match golden standard!"