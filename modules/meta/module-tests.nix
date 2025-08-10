# Per-module testing framework
# Validates individual modules against Dendritic Pattern requirements
{ config, lib, pkgs, ... }:
let
  # Test individual module compliance
  testModule = path: name: namespace: pkgs.runCommand "test-${name}" {} ''
    echo "Testing module: ${name}"
    
    # Check 1: File exists
    test -f ${path} || (echo "✗ Module file not found: ${path}" && exit 1)
    echo "✓ Module file exists"
    
    # Check 2: Correct namespace
    if grep -q "flake.modules.nixos.${namespace}" ${path}; then
      echo "✓ Correct namespace: ${namespace}"
    else
      echo "✗ Wrong namespace in ${name} (expected ${namespace})"
      exit 1
    fi
    
    # Check 3: No desktop namespace
    if grep -q "flake.modules.nixos.desktop" ${path}; then
      echo "✗ Desktop namespace found in ${name} (forbidden)"
      exit 1
    else
      echo "✓ No desktop namespace"
    fi
    
    # Check 4: Has pipe operators (if applicable)
    if grep -q "pkgs\." ${path} && ! grep -q "|>" ${path}; then
      echo "⚠ Missing pipe operators in ${name}"
    else
      echo "✓ Pipe operators present or not needed"
    fi
    
    # Check 5: No mkForce
    if grep -q "mkForce" ${path}; then
      echo "✗ mkForce found in ${name} (use mkDefault)"
      exit 1
    else
      echo "✓ No mkForce usage"
    fi
    
    mkdir -p $out
    echo "Module ${name} passes all tests" > $out/result
  '';
  
  # Define all module tests
  moduleTests = {
    # Base modules
    "boot-visuals" = testModule ../../modules/boot/boot-visuals.nix "boot-visuals" "base";
    "efi" = testModule ../../modules/boot/efi.nix "efi" "base";
    "tmp" = testModule ../../modules/boot/tmp.nix "tmp" "base";
    "swap" = testModule ../../modules/storage/swap.nix "swap" "base";
    "nix-package" = testModule ../../modules/base/nix-package.nix "nix-package" "base";
    "nix-settings" = testModule ../../modules/base/nix-settings.nix "nix-settings" "base";
    
    # PC modules
    "audio-pipewire" = testModule ../../modules/audio/audio-pipewire.nix "audio-pipewire" "pc";
    "plasma" = testModule ../../modules/window-manager/plasma.nix "plasma" "pc";
    "applications" = testModule ../../modules/applications/applications.nix "applications" "pc";
    "networking" = testModule ../../modules/networking/networking.nix "networking" "pc";
    "unfree" = testModule ../../modules/pc/unfree-packages.nix "unfree" "pc";
    "color-scheme" = testModule ../../modules/style/color-scheme.nix "color-scheme" "pc";
    
    # Workstation modules
    "security-tools" = testModule ../../modules/security/security-tools.nix "security-tools" "workstation";
    "docker" = testModule ../../modules/virtualization/docker.nix "docker" "workstation";
    "development" = testModule ../../modules/development/development.nix "development" "workstation";
  };
  
  # Aggregate all tests
  allModuleTests = pkgs.symlinkJoin {
    name = "all-module-tests";
    paths = lib.attrValues moduleTests;
  };
in
{
  flake.modules.nixos.base = { ... }: {
    # Expose individual module tests
    system.build.moduleTests = moduleTests;
    
    # Aggregate test runner
    system.build.allModuleTests = allModuleTests;
    
    # CI test runner script
    system.build.runModuleTests = pkgs.writeShellScriptBin "run-module-tests" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      
      echo "═══════════════════════════════════════════════════════════════"
      echo "  Dendritic Pattern Module Compliance Test Suite"
      echo "═══════════════════════════════════════════════════════════════"
      echo ""
      
      PASS=0
      FAIL=0
      TOTAL=${toString (lib.length (lib.attrNames moduleTests))}
      
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: test: ''
        echo "Testing ${name}..."
        if ${test}/bin/* 2>/dev/null; then
          echo "  ✅ PASS"
          PASS=$((PASS + 1))
        else
          echo "  ❌ FAIL"
          FAIL=$((FAIL + 1))
        fi
        echo ""
      '') moduleTests)}
      
      echo "═══════════════════════════════════════════════════════════════"
      echo "Results: $PASS/$TOTAL passed, $FAIL failed"
      
      if [ $FAIL -eq 0 ]; then
        echo "🎉 All module tests passed! 100/100 compliance achieved!"
        exit 0
      else
        echo "❌ Some tests failed. Not 100/100 compliant."
        exit 1
      fi
    '';
    
    # Integration with nixos-rebuild
    system.extraSystemBuilderCmds = ''
      echo "Running Dendritic Pattern module tests..."
      ${allModuleTests}
    '';
  };
}