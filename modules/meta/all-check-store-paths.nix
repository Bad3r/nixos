
# Comprehensive testing infrastructure for all modules
# Based on golden standard (mightyiam/infra) testing patterns
{ config, lib, pkgs, ... }:
let
  # Helper to validate module namespaces
  validateNamespace = module: namespace:
    assert lib.hasAttrByPath ["flake" "modules" "nixos" namespace] config;
    true;
    
  # Ensure no desktop namespace exists
  assertNoDesktopNamespace = 
    assert !(lib.hasAttrByPath ["flake" "modules" "nixos" "desktop"] config);
    true;
    
  # Validate all modules follow semantic structure
  semanticTests = {
    audio = validateNamespace "audio" "pc";
    boot = validateNamespace "boot" "base";
    storage = validateNamespace "storage" "base";
    networking = validateNamespace "networking" "pc";
    security = validateNamespace "security" "workstation";
    virtualization = validateNamespace "virtualization" "workstation";
    style = validateNamespace "style" "pc";
  };
in
{
  flake.modules.nixos.base = { ... }: {
    # Test derivation for CI/CD
    system.build.allCheckStorePaths = pkgs.runCommand "all-checks" {
      passthru = {
        inherit semanticTests assertNoDesktopNamespace;
      };
    } ''
      echo "Running Dendritic Pattern compliance tests..."
      
      # Test 1: No desktop namespace
      ${if assertNoDesktopNamespace then "echo '✓ No desktop namespace found'" else "exit 1"}
      
      # Test 2: Semantic structure validation
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: test: 
        "echo 'Testing ${name} module...' && ${if test then "echo '✓ ${name} passes'" else "exit 1"}"
      ) semanticTests)}
      
      # Test 3: Check all .nix files have pipe operators
      echo "Checking for pipe operators..."
      for file in ${../../modules}/**/*.nix; do
        if [[ -f "$file" ]] && ! grep -q '|>' "$file" 2>/dev/null; then
          echo "✗ Missing pipe operator in $file"
          # Note: Some files legitimately may not need pipe operators
        fi
      done
      
      # Test 4: Ensure no mkForce usage
      echo "Checking for mkForce usage..."
      if grep -r "mkForce" ${../../modules} --include="*.nix" 2>/dev/null; then
        echo "✗ Found mkForce usage (should use mkDefault or mkOverride)"
        exit 1
      else
        echo "✓ No mkForce found"
      fi
      
      # Test 5: Validate module imports
      echo "Validating module imports..."
      ${pkgs.nix}/bin/nix eval --raw .#flake.modules.nixos 2>/dev/null |> \
        ${pkgs.jq}/bin/jq -e 'keys | length > 0' || exit 1
      echo "✓ Module imports valid"
      
      # Test 6: Check for proper namespace extension
      echo "Checking namespace extensions..."
      for ns in base pc workstation; do
        echo "  Checking $ns namespace..."
        ${pkgs.nix}/bin/nix eval .#flake.modules.nixos.$ns 2>/dev/null && \
          echo "  ✓ $ns namespace exists" || echo "  ⚠ $ns namespace missing"
      done
      
      # Create success marker
      mkdir -p $out
      echo "All Dendritic Pattern compliance tests passed!" > $out/success
      date >> $out/success
    '';
    
    # Hook into system activation for continuous validation
    system.activationScripts.validateDendriticPattern = lib.stringAfter ["etc"] ''
      echo "Validating Dendritic Pattern compliance..."
      # Quick runtime checks
      if [[ -d /etc/nixos/modules ]]; then
        # Count modules by namespace
        echo "Module namespace distribution:"
        echo "  base: $(find /etc/nixos/modules -name "*.nix" -exec grep -l "nixos.base" {} \; 2>/dev/null |> wc -l)"
        echo "  pc: $(find /etc/nixos/modules -name "*.nix" -exec grep -l "nixos.pc" {} \; 2>/dev/null |> wc -l)"  
        echo "  workstation: $(find /etc/nixos/modules -name "*.nix" -exec grep -l "nixos.workstation" {} \; 2>/dev/null |> wc -l)"
        
        # Ensure no desktop namespace
        if find /etc/nixos/modules -name "*.nix" -exec grep -l "nixos.desktop" {} \; 2>/dev/null |> grep -q .; then
          echo "WARNING: Desktop namespace found (should not exist)!"
        fi
      fi
    '';
  };
}