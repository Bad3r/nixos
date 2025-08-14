# Dendritic Pattern Remediation Plan

## Achieving 100/100 Golden Standard Compliance

### Executive Summary

This plan addresses all violations identified in QA_REPORT.md to achieve perfect 100/100 compliance with the mightyiam/infra golden standard Dendritic Pattern implementation.

**Current Score:** 95/100  
**Target Score:** 100/100  
**Estimated Time:** 3-4 hours  
**Risk Level:** MEDIUM (boot configuration changes require careful handling)

---

## Phase 1: Critical Violations Resolution

### 1.1 Filesystem Configuration Duplication [CRITICAL]

**Issue:** Lines 25-40 in `modules/system76/imports.nix` contain filesystem configuration that duplicates `filesystem.nix`

**Actions:**

1. **Backup current configuration**

   ```bash
   cp modules/system76/imports.nix modules/system76/imports.nix.backup
   cp modules/system76/filesystem.nix modules/system76/filesystem.nix.backup
   ```

2. **Remove ONLY filesystem configuration from imports.nix**

   - Keep boot.loader configuration (lines 14-23) - it's not duplicated
   - Delete ONLY fileSystems configuration block (lines 25-40)
   - Preserve the imports array and boot configuration

3. **Verify filesystem.nix has the removed configuration**

   ```bash
   # Confirm filesystem.nix contains all filesystem mounts
   grep -E "fileSystems\." modules/system76/filesystem.nix
   # Should show all filesystem mount points
   ```

4. **Test build after removal**
   ```bash
   nix build .#nixosConfigurations.system76.config.system.build.toplevel \
     --extra-experimental-features "nix-command flakes pipe-operators"
   ```

**Verification:**

- imports.nix retains boot.loader configuration
- imports.nix has no fileSystems configuration
- filesystem.nix contains all filesystem mounts
- System builds successfully

---

### 1.2 Host-Specific Configuration Architecture

**Issue:** Need to align with golden standard while preserving host-specific UUIDs

**Decision:** Keep filesystem.nix in system76/ directory (host-specific configuration)

**Actions:**

1. **Verify current structure is correct**

   ```bash
   # Confirm filesystem.nix is properly namespaced
   grep "flake.modules.nixos" modules/system76/filesystem.nix
   # Should show: flake.modules.nixos."configurations.nixos.system76"
   ```

2. **No changes needed to filesystem.nix location**
   - Host-specific UUIDs belong in host directory
   - Golden standard uses generic storage/ for ZFS configuration
   - Our UUID-based configuration is correctly placed

**Verification:**

- modules/system76/filesystem.nix remains in place
- Proper namespace: `configurations.nixos.system76`

---

## Phase 2: Test Infrastructure Migration

### 2.1 Remove Tests Directory

**Issue:** Golden standard uses flake checks, not shell scripts

**Actions:**

1. **Archive existing tests**

   ```bash
   tar -czf tests-archive-$(date +%Y%m%d).tar.gz tests/
   ```

2. **Migrate dendritic compliance test to flake check**

   Create or update `modules/meta/checks.nix`:

   ```nix
   { lib, ... }:
   {
     perSystem = { pkgs, ... }: {
       checks.dendritic-compliance = pkgs.runCommand "dendritic-compliance-check" {} ''
         # Check for module headers (should find none)
         HEADERS=$(find ${../..}/modules -name "*.nix" -exec head -n1 {} \; | grep -c "^#" || true)
         if [ "$HEADERS" -ne 0 ]; then
           echo "ERROR: Found $HEADERS files with comment headers"
           exit 1
         fi

         # Verify abort-on-warn
         if ! grep -q "abort-on-warn.*=.*true" ${../..}/flake.nix; then
           echo "ERROR: abort-on-warn not set to true"
           exit 1
         fi

         # Verify pipe-operators
         if ! grep -q "pipe-operators" ${../..}/flake.nix; then
           echo "ERROR: pipe-operators not enabled"
           exit 1
         fi

         echo "Dendritic compliance: PASSED" > $out
       '';
     };
   }
   ```

3. **Remove tests directory**
   ```bash
   rm -rf tests/
   ```

**Verification:**

- tests/ directory no longer exists
- `nix flake check` runs the compliance test
- No shell scripts remain

---

## Phase 3: Scripts Directory Cleanup

### 3.1 Remove Scripts Directory

**Issue:** Scripts directory not present in golden standard

**Actions:**

1. **Archive utility scripts**

   ```bash
   tar -czf scripts-archive-$(date +%Y%m%d).tar.gz scripts/
   ```

2. **Evaluate script necessity**

   - add-module-headers.sh - DELETE (anti-pattern, headers removed)
   - generate-dependency-graph.sh - MIGRATE to flake app if needed
   - simplify-headers.sh - DELETE (headers already removed)

3. **Remove scripts directory**
   ```bash
   rm -rf scripts/
   ```

**Verification:**

- scripts/ directory no longer exists
- No functional regression

---

## Phase 4: Validation and Verification

### 4.1 Compliance Testing

**Actions:**

1. **Run full system build**

   ```bash
   nix build .#nixosConfigurations.system76.config.system.build.toplevel \
     --extra-experimental-features "nix-command flakes pipe-operators"
   ```

2. **Verify flake checks**

   ```bash
   nix flake check --extra-experimental-features "nix-command flakes pipe-operators"
   ```

3. **Validate module structure**

   ```bash
   # Count total modules (golden standard has ~200)
   find modules -name "*.nix" -type f | wc -l

   # Verify no storage namespace exists (we keep host-specific)
   grep -r "flake.modules.nixos.storage" modules/ || echo "Good: No storage namespace"

   # Verify system76 namespace is correct
   grep "configurations.nixos.system76" modules/system76/*.nix | wc -l

   # Check for any remaining headers
   find modules -name "*.nix" -exec head -n1 {} \; | grep "^#" || echo "Good: No headers"
   ```

4. **Verify no duplicate configurations**
   ```bash
   # Ensure filesystem config only in filesystem.nix
   grep -l "fileSystems\." modules/system76/*.nix
   # Should only show: modules/system76/filesystem.nix
   ```

### 4.2 Golden Standard Alignment Verification

**Checklist:**

- [ ] No filesystem config in imports.nix (only boot.loader remains)
- [ ] filesystem.nix remains in system76/ (host-specific)
- [ ] tests/ directory removed
- [ ] scripts/ directory removed
- [ ] All modules start with Nix code (no headers)
- [ ] abort-on-warn = true in flake.nix
- [ ] pipe-operators enabled
- [ ] No explicit imports (only namespace references)
- [ ] System builds successfully
- [ ] Flake checks pass
- [ ] Boot configuration preserved and functional

---

## Phase 5: Optional Enhancements

### 5.1 Feature Parity Analysis

**Consider adding from golden standard:**

1. **bluetooth.nix** - Bluetooth support module
2. **vim-mode.nix** - Enhanced vim configuration
3. **UI toolkit modules** - gtk.nix, qt.nix for better theming
4. **Additional networking** - Extended network management

**Decision Framework:**

- Only add if actively needed
- Maintain minimal surface area
- Follow exact golden standard patterns

---

## Rollback Plan

If any issues occur:

1. **Phase 1 Rollback (Filesystem/Boot Issues)**

   ```bash
   # Restore original imports.nix with all configurations
   cp modules/system76/imports.nix.backup modules/system76/imports.nix

   # Restore original filesystem.nix if modified
   cp modules/system76/filesystem.nix.backup modules/system76/filesystem.nix

   # Verify boot configuration is intact
   grep -A10 "boot.loader" modules/system76/imports.nix
   ```

2. **Phase 2-3 Rollback (Test/Scripts Recovery)**

   ```bash
   # Restore tests directory if needed
   tar -xzf tests-archive-*.tar.gz

   # Restore scripts directory if needed
   tar -xzf scripts-archive-*.tar.gz

   # Remove any added flake checks if they cause issues
   git restore modules/meta/checks.nix
   ```

3. **Full System Verification**

   ```bash
   # Ensure system builds
   nix build .#nixosConfigurations.system76.config.system.build.toplevel \
     --extra-experimental-features "nix-command flakes pipe-operators"

   # Verify boot configuration
   nix eval .#nixosConfigurations.system76.config.boot.loader

   # Check filesystem mounts
   nix eval .#nixosConfigurations.system76.config.fileSystems
   ```

4. **Emergency Recovery**

   ```bash
   # If system won't build, use previous generation
   sudo nixos-rebuild boot --rollback

   # Or restore from git
   git stash  # Save current changes
   git checkout HEAD -- modules/  # Restore all modules
   ```

---

## Success Criteria

**100/100 Compliance Achieved When:**

1. ✅ No duplicate filesystem configuration
2. ✅ Filesystem configuration properly isolated in system76/filesystem.nix
3. ✅ No tests/ directory (migrated to flake checks)
4. ✅ No scripts/ directory
5. ✅ System builds successfully
6. ✅ All flake checks pass
7. ✅ Directory structure matches golden standard
8. ✅ QA_REPORT.md shows 100/100 score

---

## Execution Timeline

| Phase  | Task                           | Duration | Dependencies |
| ------ | ------------------------------ | -------- | ------------ |
| 1.1    | Remove filesystem duplication  | 30 min   | None         |
| 1.2    | Verify host-specific structure | 15 min   | 1.1          |
| 2.1    | Migrate tests to flake checks  | 90 min   | None         |
| 3.1    | Remove scripts directory       | 15 min   | None         |
| 4.1    | Full validation                | 30 min   | All above    |
| 4.2    | Golden standard verification   | 20 min   | 4.1          |
| Buffer | Testing and debugging          | 40 min   | Throughout   |

**Total Estimated Time:** 3-4 hours

---

## Risk Mitigation

**Risk Assessment:**

- **Boot Configuration:** MEDIUM risk - careful handling required
- **Filesystem Changes:** LOW risk - only removing duplicates
- **Test Migration:** LOW risk - non-critical functionality
- **Scripts Removal:** LOW risk - utility scripts only

**Mitigation Strategy:**

- Comprehensive backups before each change
- Boot configuration preserved in imports.nix
- Test build after each critical change
- Detailed rollback procedures for each phase
- Git history provides ultimate safety net

**Testing Protocol:**

- Build test after Phase 1.1 (critical)
- Flake check after Phase 2.1
- Full validation after all phases
- Boot configuration verification throughout

---

## Post-Implementation

After achieving 100/100:

1. Update CLAUDE.md with final state
2. Remove backup files
3. Document in git commit: "feat: achieve 100/100 Dendritic Pattern compliance"
4. Run final QA_REPORT.md generation
5. Celebrate perfect golden standard alignment! 🎉
