
{ inputs, lib, ... }:
{
  imports = lib.optional (inputs ? git-hooks) inputs.git-hooks.flakeModule;
  
  perSystem = { config, pkgs, ... }: {
    pre-commit = lib.mkIf (inputs ? git-hooks) {
      check.enable = true;
      settings = {
        hooks = {
          # Nix formatting
          nixpkgs-fmt = {
            enable = true;
            description = "Format Nix files";
          };
          
          # Dead code detection
          deadnix = {
            enable = true;
            description = "Find dead Nix code";
          };
          
          # Static analysis
          statix = {
            enable = true;
            description = "Lint Nix files";
          };
          
          # Custom dendritic compliance check
          dendritic-check = {
            enable = true;
            name = "dendritic-compliance";
            entry = "${pkgs.writeShellScript "dendritic-check" ''
              #!/usr/bin/env bash
              set -euo pipefail
              
              # Check for wrong namespaces
              if grep -r "flake.modules.nixos.desktop" modules/ --include="*.nix" 2>/dev/null; then
                echo "ERROR: Found desktop namespace (should be eliminated)"
                exit 1
              fi
              
              # Check for literal imports
              if grep -r "imports.*\./" modules/ --include="*.nix" 2>/dev/null | grep -v "^#"; then
                echo "ERROR: Found literal path imports"
                exit 1
              fi
              
              # Check mkForce usage
              MKFORCE_COUNT=$(grep -r "mkForce" modules/ --include="*.nix" 2>/dev/null | wc -l || echo "0")
              if [ "$MKFORCE_COUNT" -gt 0 ]; then
                echo "WARNING: Found $MKFORCE_COUNT mkForce usages - consider mkDefault"
              fi
              
              echo "✓ Dendritic pattern compliance check passed"
            ''}";
            files = "\\.(nix)$";
            pass_filenames = false;
          };
        };
        
        # Exclude generated files
        excludes = [
          "flake.lock"
          "result"
          "result-*"
        ];
      };
    };
  };
}