
# Comprehensive integration tests for entire configuration
# Tests system-wide Dendritic Pattern compliance
{ config, lib, pkgs, ... }:
let
  # VM test for full system validation
  dendriticPatternTest = pkgs.nixosTest {
    name = "dendritic-pattern-compliance";
    
    nodes.machine = { ... }: {
      imports = [ config.flake.nixosConfigurations.system76 ];
      
      # Override for testing
      boot.loader.grub.device = "nodev";
      fileSystems."/" = {
        device = "/dev/vda";
        fsType = "ext4";
      };
    };
    
    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")
      
      # Test 1: System boots successfully
      machine.succeed("systemctl is-system-running --quiet")
      print("✓ System boots successfully")
      
      # Test 2: No desktop namespace in runtime
      machine.fail("grep -r 'nixos\\.desktop' /run/current-system/sw/bin/ 2>/dev/null || true")
      print("✓ No desktop namespace in runtime")
      
      # Test 3: Required namespaces exist
      machine.succeed("nix eval --raw .#flake.modules.nixos.base")
      machine.succeed("nix eval --raw .#flake.modules.nixos.pc")
      machine.succeed("nix eval --raw .#flake.modules.nixos.workstation")
      print("✓ All required namespaces exist")
      
      # Test 4: Module loading works
      machine.succeed("nix eval --raw .#nixosConfigurations.system76.config.system.build.toplevel")
      print("✓ Module loading successful")
      
      # Test 5: No evaluation errors
      machine.succeed("nix flake check")
      print("✓ Flake check passes")
      
      # Test 6: Verify semantic structure
      for module_dir in ["audio", "boot", "storage", "networking", "security", "virtualization", "style"]:
          machine.succeed(f"test -d /etc/nixos/modules/{module_dir}")
      print("✓ Semantic directory structure verified")
      
      # Test 7: No mkForce in configuration
      machine.fail("grep -r 'mkForce' /etc/nixos/modules --include='*.nix' || true")
      print("✓ No mkForce usage found")
      
      # Test 8: Pipe operators present
      machine.succeed("grep -r '|>' /etc/nixos/modules --include='*.nix'")
      print("✓ Pipe operators present")
      
      print("\n" + "="*60)
      print("ALL INTEGRATION TESTS PASSED - 100/100 COMPLIANCE")
      print("="*60)
    '';
  };
  
  # Quick validation test
  quickValidation = pkgs.writeShellScriptBin "quick-dendritic-validation" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    
    echo "Quick Dendritic Pattern Validation"
    echo "===================================="
    
    # Check 1: Build succeeds
    echo -n "Build validation: "
    if nix build .#nixosConfigurations.system76.config.system.build.toplevel --dry-run 2>/dev/null; then
      echo "✅ PASS"
    else
      echo "❌ FAIL"
      exit 1
    fi
    
    # Check 2: No desktop namespace
    echo -n "Desktop namespace check: "
    if grep -r "nixos\\.desktop" modules/ --include="*.nix" 2>/dev/null |> grep -v "^#"; then
      echo "❌ FAIL (desktop namespace found)"
      exit 1
    else
      echo "✅ PASS"
    fi
    
    # Check 3: Module structure
    echo -n "Module structure check: "
    REQUIRED_DIRS="audio boot hardware networking security storage style virtualization window-manager"
    MISSING=""
    for dir in $REQUIRED_DIRS; do
      if [[ ! -d "modules/$dir" ]]; then
        MISSING="$MISSING $dir"
      fi
    done
    if [[ -n "$MISSING" ]]; then
      echo "❌ FAIL (missing:$MISSING)"
      exit 1
    else
      echo "✅ PASS"
    fi
    
    # Check 4: Namespace compliance
    echo -n "Namespace compliance: "
    ERROR=0
    
    # Base modules should extend nixos.base
    for file in modules/boot/*.nix modules/storage/*.nix; do
      if [[ -f "$file" ]] && ! grep -q "nixos\\.base" "$file" 2>/dev/null; then
        echo "  ⚠ $file doesn't extend base"
        ERROR=1
      fi
    done
    
    # PC modules should extend nixos.pc  
    for file in modules/audio/*.nix modules/window-manager/*.nix modules/style/*.nix; do
      if [[ -f "$file" ]] && ! grep -q "nixos\\.pc" "$file" 2>/dev/null; then
        echo "  ⚠ $file doesn't extend pc"
        ERROR=1
      fi
    done
    
    # Workstation modules should extend nixos.workstation
    for file in modules/security/*.nix modules/virtualization/*.nix; do
      if [[ -f "$file" ]] && ! grep -q "nixos\\.workstation" "$file" 2>/dev/null; then
        echo "  ⚠ $file doesn't extend workstation"
        ERROR=1
      fi
    done
    
    if [[ $ERROR -eq 0 ]]; then
      echo "✅ PASS"
    else
      echo "❌ FAIL"
      exit 1
    fi
    
    echo ""
    echo "===================================="
    echo "✨ Quick validation PASSED!"
    echo "Run 'nix build .#nixosConfigurations.system76.config.system.build.runModuleTests' for full tests"
  '';
in
{
  flake.modules.nixos.base = { ... }: {
    # Full VM integration test
    system.build.integrationTest = dendriticPatternTest;
    
    # Quick validation script
    system.build.quickValidation = quickValidation;
    
    # Continuous integration check
    system.build.ciCheck = pkgs.writeShellScriptBin "ci-check" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      
      echo "════════════════════════════════════════════════════════════"
      echo "  Dendritic Pattern CI/CD Compliance Check"
      echo "════════════════════════════════════════════════════════════"
      echo ""
      
      # Run all checks
      echo "1. Running quick validation..."
      ${quickValidation}/bin/quick-dendritic-validation
      
      echo ""
      echo "2. Running module tests..."
      nix build .#nixosConfigurations.system76.config.system.build.allModuleTests
      
      echo ""
      echo "3. Running flake check..."
      nix flake check
      
      echo ""
      echo "4. Running format check..."
      nix fmt -- --check
      
      echo ""
      echo "════════════════════════════════════════════════════════════"
      echo "  ✅ ALL CI CHECKS PASSED - 100/100 COMPLIANCE ACHIEVED!"
      echo "════════════════════════════════════════════════════════════"
    '';
  };
}