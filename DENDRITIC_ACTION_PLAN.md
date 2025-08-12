# Dendritic Pattern Compliance Action Plan: Path to 100/100

**Plan Version:** 3.0
**Target Score:** 100/100
**Current Score:** 85/100
**Estimated Completion:** 5-6 weeks
**Golden Standard Reference:** `/home/vx/git/infra`

---

## Executive Summary

This comprehensive action plan addresses all 11 identified issues from the ULTRATHINK QA analysis to achieve perfect 100/100 Dendritic Pattern compliance. Every action is validated against the golden standard implementation at `/home/vx/git/infra`. All commands include mandatory pipe-operators flag.

---

## Phase 0: Pre-Flight Checklist and System State Capture

### System State Capture
```bash
# Capture initial state for comparison
nixos-rebuild list-generations > initial-generations.txt
nix-store --gc --print-roots | grep -v '/proc/' > initial-roots.txt
df -h /nix/store > initial-disk.txt
nix eval .#nixosConfigurations.system76.config.system.stateVersion --extra-experimental-features pipe-operators

# Measure current score
./test-dendritic-compliance.sh > initial-compliance.txt
```

### Cleanup Existing Artifacts
```bash
# Remove temporary files and old backups
rm -f modules/meta/generation-manager.nix.tmp
rm -rf modules.backup.headers.20250810-234932/
rm -rf modules.backup.simplify.20250811-001545/

# Review shell scripts for consolidation
ls -la *.sh | grep -E "(add-module|simplify)" 
# Decision: Consolidate into single header-management.sh script
```

### Full System Backup
```bash
# Create restore point
cp -r /home/vx/nixos /home/vx/nixos.backup.$(date +%Y%m%d)
git add modules/**/*.nix  # Specific, not -A
git commit -m "Pre-migration checkpoint"
```

---

## Pre-Flight Golden Standard Validation

**MANDATORY FIRST STEP:** Verify all changes against golden standard

```bash
# Clone golden standard if not available
if [ ! -d "/home/vx/git/infra" ]; then
  git clone https://github.com/mightyiam/infra /home/vx/git/infra
fi

# Create comparison baseline
find /home/vx/git/infra/modules -name "*.nix" -type f | sort > golden-modules.txt
find /home/vx/nixos/modules -name "*.nix" -type f | sort > current-modules.txt

# Verify import-tree functionality
nix eval .#flake.modules --extra-experimental-features pipe-operators --json | jq 'keys' > initial-modules.json
```

---

## Phase 1: Critical Fixes (Week 1)
**Goal:** Fix all CRITICAL issues that violate core Dendritic Pattern principles
**Rollback Strategy:** 
- Git commit after each successful fix
- System generation rollback: `sudo nixos-rebuild switch --rollback`
- Partial rollback: `git checkout HEAD~1 -- specific/file.nix`

### 1.1 Verify nvidia-gpu.nix Against Golden Standard
**Priority:** CRITICAL
**Time:** 2 hours
**Files:** `/home/vx/nixos/modules/nvidia-gpu.nix`

**Golden Standard Analysis:**
```bash
# Step 1: Compare with golden standard
diff -u modules/nvidia-gpu.nix /home/vx/git/infra/modules/nvidia-gpu.nix

# Step 2: Verify pattern - nixpkgs.allowedUnfreePackages MAY be outside namespace
# This is CORRECT per golden standard:
grep -A5 -B5 "allowedUnfreePackages" /home/vx/git/infra/modules/nvidia-gpu.nix
```

**Actions:**
1. The QA report may be incorrect - the golden standard has `nixpkgs.allowedUnfreePackages` OUTSIDE the namespace
2. Verify current implementation matches golden standard
3. If different, adopt golden standard pattern exactly
4. Test with: `nix flake check --extra-experimental-features pipe-operators`

**Validation:**
```bash
# After any changes
git add modules/nvidia-gpu.nix
git commit -m "Phase 1.1: Align nvidia-gpu.nix with golden standard"
nix flake check --extra-experimental-features pipe-operators || git reset --hard HEAD~1

# Verify import-tree still works
nix eval .#flake.modules --extra-experimental-features pipe-operators --json | jq 'keys' > post-phase1.1-modules.json
diff initial-modules.json post-phase1.1-modules.json
```

### 1.2 Fix efi.nix HomeManager Pollution
**Priority:** CRITICAL
**Time:** 2 hours
**Files:** `/home/vx/nixos/modules/boot/efi.nix`

**Golden Standard Verification:**
```bash
# Check if golden standard has efi module and its pattern
find /home/vx/git/infra -name "efi.nix" -exec cat {} \;
# If not found, check similar boot modules for pattern
ls -la /home/vx/git/infra/modules/boot/
```

**Actions:**
1. Named modules (like efi) should NOT modify other namespaces
2. Remove any `flake.modules.homeManager.base` references from efi.nix
3. Ensure efi module only exports to `flake.modules.nixos.efi`
4. If home packages are truly needed, document why in module header

**Implementation:**
```nix
# modules/boot/efi.nix should ONLY contain:
{ ... }:
{
  flake.modules.nixos.efi = {
    # EFI-specific configuration only
    boot.loader.systemd-boot.enable = true;
    # ... other EFI config
  };
  # NO other namespace modifications
}
```

**Validation:**
```bash
git add modules/boot/efi.nix
git commit -m "Phase 1.2: Remove cross-namespace pollution from efi.nix"
nix flake check --extra-experimental-features pipe-operators || git reset --hard HEAD~1

# Verify import-tree still works
nix eval .#flake.modules --extra-experimental-features pipe-operators --json | jq 'keys' > post-phase1.2-modules.json
diff initial-modules.json post-phase1.2-modules.json
```

### 1.3 Remove All "desktop" Namespace References
**Priority:** CRITICAL
**Time:** 1.5 hours
**Files:** All files containing "desktop" references

**Comprehensive Search:**
```bash
# Search ENTIRE repository with all variations
grep -r "desktop" . --include="*.nix" --exclude-dir=.git --exclude-dir=result
grep -r "\.desktop\b" . --include="*.nix" --exclude-dir=.git --exclude-dir=result
grep -r "modules\.desktop" . --include="*.nix" --exclude-dir=.git --exclude-dir=result
grep -r "flake\.modules\.desktop" . --include="*.nix" --exclude-dir=.git --exclude-dir=result
# Also check markdown files
grep -r "desktop" . --include="*.md" --exclude-dir=.git
```

**Actions:**
1. Replace ALL occurrences of "desktop" namespace with "pc"
2. Update references in:
   - `/home/vx/nixos/modules/meta/module-tests.nix` (lines 3, 27)
   - `/home/vx/nixos/modules/meta/git-hooks.nix` (line 39)
   - Any other files found
3. Update documentation if needed

**Verification:**
```bash
# Ensure zero results
grep -r "desktop" . --include="*.nix" --exclude-dir=.git --exclude-dir=result
[ $? -eq 1 ] || echo "ERROR: desktop references still exist!"
```

**Validation:**
```bash
git status  # Review changes first
git add modules/**/*.nix  # Add only module files
git commit -m "Phase 1.3: Remove all forbidden 'desktop' namespace references"
nix flake check --extra-experimental-features pipe-operators || git reset --hard HEAD~1

# Verify import-tree still works
nix eval .#flake.modules --extra-experimental-features pipe-operators --json | jq 'keys' > post-phase1.3-modules.json
diff initial-modules.json post-phase1.3-modules.json
```

### 1.4 Correct module-tests.nix Header and Structure
**Priority:** CRITICAL
**Time:** 30 minutes
**Files:** `/home/vx/nixos/modules/meta/module-tests.nix`

**Actions:**
1. Fix the incorrect header (currently says "Docker containerization platform configuration")
2. Verify test approach against golden standard
3. Ensure namespace documentation is accurate

**Golden Standard Check:**
```bash
# Check how golden standard handles tests
grep -r "flake.checks" /home/vx/git/infra/modules/
cat /home/vx/git/infra/modules/home-manager/checks.nix
```

**Correct Header:**
```nix
# Module: meta/module-tests.nix
# Purpose: Module testing framework for Dendritic Pattern compliance
# Namespace: flake.checks
# Pattern: Validates dendritic pattern implementation across all modules
```

**Validation:**
```bash
git add modules/meta/module-tests.nix
git commit -m "Phase 1.4: Fix module-tests.nix header and documentation"
nix flake check --extra-experimental-features pipe-operators || git reset --hard HEAD~1

# Verify import-tree still works after Phase 1 complete
nix eval .#flake.modules --extra-experimental-features pipe-operators --json | jq 'keys' > post-phase1-modules.json
diff initial-modules.json post-phase1-modules.json
```

---

## Phase 2: High Priority Fixes (Week 2)

### 2.1 Add Documentation Headers to All Modules
**Priority:** HIGH
**Time:** 3 days
**Files:** 60+ modules without headers

**Golden Standard Header Analysis:**
```bash
# Comprehensive header pattern analysis
head -20 /home/vx/git/infra/modules/*/*.nix | grep "^#" | sort -u > golden-headers.txt
# Check consistency across golden standard
for file in /home/vx/git/infra/modules/**/*.nix; do
  echo "File: $file"
  head -5 "$file" | grep "^#" || echo "No header"
done > golden-header-analysis.txt
# Adopt most common pattern or no headers if golden standard doesn't use them
```

**Actions:**
1. First verify header pattern from golden standard
2. Create header template matching golden standard
3. Apply to all modules systematically:
   - `/virtualization/` (2 files)
   - `/security/` (2 files)
   - `/storage/` (1 file - swap.nix)
   - `/networking/` (2 files)
   - `/home/` subdirectories (40+ files)
4. Review each header for accuracy

**Header Template (Match Golden Standard):**
```nix
# Module: [category/filename.nix]
# Purpose: [Clear, specific description]
# Namespace: flake.modules.[nixos|homeManager].[base|pc|workstation|"name"]
# Pattern: [Specific dendritic pattern aspect implemented]
```

**Automation Script Enhancement:**
```bash
#!/usr/bin/env bash
# Enhanced add-module-headers.sh
for file in modules/**/*.nix; do
  if ! grep -q "^# Module:" "$file"; then
    # Determine namespace from path
    namespace=$(determine_namespace "$file")
    # Add header
    add_header "$file" "$namespace"
  fi
done
```

### 2.2 Complete Test Framework Redesign
**Priority:** HIGH
**Time:** 3-5 days
**Files:** `/home/vx/nixos/modules/meta/module-tests.nix`

**CRITICAL:** The test framework needs complete redesign, not just path replacement

**Golden Standard Test Pattern:**
```bash
# Study golden standard testing approach
cat /home/vx/git/infra/modules/home-manager/checks.nix
grep -r "flake.checks" /home/vx/git/infra/
```

**Actions:**
1. Study golden standard's check-based testing approach
2. Redesign tests to use flake checks system
3. Remove ALL hardcoded paths
4. Implement module validation through flake.checks namespace

**New Approach (Based on Golden Standard):**
```nix
# modules/meta/module-tests.nix
{ config, ... }:
{
  flake.checks = {
    # Use module references directly, not paths
    base-modules = config.flake.modules.nixos.base;
    pc-modules = config.flake.modules.nixos.pc;
    # Validation logic here
  };
}
```

**Note:** This is a FUNDAMENTAL REDESIGN, not a simple refactor

### 2.3 Increase Metadata Usage
**Priority:** HIGH
**Time:** 4-5 days
**Target:** From 14 to 50+ modules using metadata

**Actions:**
1. Audit all modules for hardcoded values:
   ```bash
   grep -r '"vx"' modules/ --include="*.nix"
   grep -r '"Asia/Riyadh"' modules/ --include="*.nix"
   grep -r "6234" modules/ --include="*.nix"  # SSH port
   ```
2. Create metadata migration checklist
3. Update each module to use `config.flake.meta`
4. Add new metadata fields as needed in `meta/owner.nix`

**Common Replacements:**
- `"vx"` → `${config.flake.meta.owner.username}`
- `"Asia/Riyadh"` → `config.flake.meta.system.timezone`
- `6234` → `config.flake.meta.network.sshPort`
- `"25.05"` → `config.flake.meta.system.stateVersion`

**Validation of Metadata Changes:**
```bash
# Before changes
nix eval .#flake.meta --extra-experimental-features pipe-operators --json | jq . > meta-before.json
# After changes
nix eval .#flake.meta --extra-experimental-features pipe-operators --json | jq . > meta-after.json
diff meta-before.json meta-after.json

# Verify import-tree after Phase 2
nix eval .#flake.modules --extra-experimental-features pipe-operators --json | jq 'keys' > post-phase2-modules.json
diff initial-modules.json post-phase2-modules.json
```

---

## Phase 3: Optimization (Week 3)

### 3.1 Reorganize Misplaced Modules (If Needed)
**Priority:** MEDIUM
**Time:** 4 hours

**Golden Standard Verification First:**
```bash
# Check where golden standard places these modules
ls -la /home/vx/git/infra/modules/ | grep nvidia
ls -la /home/vx/git/infra/modules/boot/
ls -la /home/vx/git/infra/modules/storage/
```

**Actions:**
1. ONLY reorganize if different from golden standard
2. If nvidia-gpu.nix is at root in golden standard, keep it there
3. Match golden standard directory structure exactly
4. Update documentation if changes made

**If Reorganization Needed:**
```bash
# Only if golden standard has different structure
mkdir -p modules/[appropriate-directory]
mv modules/[file] modules/[appropriate-directory]/
# Test with pipe-operators
nix flake check --extra-experimental-features pipe-operators
```

### 3.2 Implement Conditional Home Manager Loading
**Priority:** MEDIUM
**Time:** 6 hours
**Files:** `/home/vx/nixos/modules/home-manager-setup.nix`

**Actions:**
1. Implement feature flag for GUI modules
2. Add conditional loading based on system type
3. Create metadata flag: `flake.meta.features.gui`
4. Test on both GUI and non-GUI configurations

**Implementation:**
```nix
{ config, lib, ... }:
{
  flake.modules.homeManager = lib.mkMerge [
    config.flake.modules.homeManager.base
    (lib.mkIf config.flake.meta.features.gui
      config.flake.modules.homeManager.gui)
  ];
}
```

### 3.3 Fix Library Prefix Inconsistencies
**Priority:** MEDIUM
**Time:** 3 hours

**Actions:**
1. Audit all modules for missing `lib.` prefixes
2. Fix `/home/vx/nixos/modules/storage/storage-redundancy.nix`
3. Search for common functions without prefix:
   ```bash
   grep -r "\bmap\b" modules/ --include="*.nix" | grep -v "lib.map"
   grep -r "\bfilter\b" modules/ --include="*.nix" | grep -v "lib.filter"
   grep -r "\bmkIf\b" modules/ --include="*.nix" | grep -v "lib.mkIf"
   grep -r "\bmkDefault\b" modules/ --include="*.nix" | grep -v "lib.mkDefault"
   ```
4. Add `lib.` prefix to all standard library functions

**Validation:**
```bash
git status  # Review changes
git add modules/**/*.nix  # Add specific files
git commit -m "Phase 3.3: Fix library prefix inconsistencies"
nix flake check --extra-experimental-features pipe-operators || git reset --hard HEAD~1

# Verify import-tree still works
nix eval .#flake.modules --extra-experimental-features pipe-operators --json | jq 'keys' > post-phase3-modules.json
diff initial-modules.json post-phase3-modules.json
```

### 3.4 Expand Test Coverage
**Priority:** MEDIUM
**Time:** 3 days
**Target:** 80% module coverage

**Actions:**
1. Create test matrix for all modules
2. Implement tests for critical modules first
3. Add integration tests for namespace composition
4. Create automated test runner
5. Add pre-commit hooks for test execution

**Test Categories:**
- Namespace validation tests
- Metadata usage tests
- Import mechanism tests
- Pattern compliance tests
- Integration tests

---

## Phase 4: Excellence (Week 4-5)

### 4.1 Implement Advanced Golden Standard Patterns
**Priority:** LOW
**Time:** 1 week

**Actions:**
1. Study mightyiam/infra repository patterns
2. Implement:
   - Per-check CI job generation
   - Dynamic store path validation
   - Input branches management
   - Zero-warning enforcement
3. Adapt patterns to current configuration
4. Document implementation decisions

### 4.2 Complete Documentation Coverage
**Priority:** LOW
**Time:** 3 days

**Actions:**
1. Ensure 100% of modules have headers
2. Create MODULE_STRUCTURE_GUIDE.md
3. Update DENDRITIC_PATTERN_GUIDE.md
4. Add inline documentation for complex logic
5. Create decision log for architecture choices

### 4.3 Security Hardening
**Priority:** LOW
**Time:** 2 days

**Actions:**
1. Implement capability controls
2. Add security assertion tests
3. Review and implement secure boot patterns
4. Audit for any remaining hardcoded secrets
5. Implement secret rotation mechanisms

### 4.4 Create Automation Tools
**Priority:** LOW
**Time:** 3 days

**Actions:**
1. Module dependency visualizer
2. Automated compliance checker
3. Pattern violation detector
4. Metadata coverage reporter
5. CI/CD pipeline for continuous validation

---

## Validation Checkpoints

### After Each Phase:
1. Run `nix flake check --extra-experimental-features pipe-operators`
2. Execute `./test-dendritic-compliance.sh`
3. Run module tests
4. Verify no regressions against golden standard
5. Commit changes: `git add -A && git commit -m "Phase X complete"`
6. Update QA_REPORT.md with progress
7. Rollback if needed: `git reset --hard HEAD~1`

### Final Validation (100/100 Checklist):
- [ ] All commands include pipe-operators flag
- [ ] Zero deviations from golden standard
- [ ] Zero namespace violations
- [ ] No "desktop" references anywhere
- [ ] All modules have correct headers (matching golden standard)
- [ ] No hardcoded paths in tests (check-based testing)
- [ ] 50+ modules using metadata
- [ ] All library functions prefixed with `lib.`
- [ ] Conditional Home Manager loading implemented
- [ ] Modules in directories matching golden standard
- [ ] 80%+ test coverage
- [ ] Advanced patterns from golden standard implemented
- [ ] 100% documentation coverage
- [ ] Performance metrics acceptable
- [ ] All existing shell scripts integrated/cleaned
- [ ] CI/CD integration complete

---

## Success Metrics

### Phase 1 Success (Day 3):
- Score increase: 85 → 90
- All CRITICAL issues resolved
- System builds without errors
- All changes match golden standard

### Phase 2 Success (Week 3):
- Score increase: 90 → 95
- All HIGH priority issues resolved
- Metadata usage > 40%
- Test framework redesigned

### Phase 3 Success (Week 4):
- Score increase: 95 → 98
- All MEDIUM priority issues resolved
- Test coverage > 80%
- Performance metrics baselined

### Phase 4 Success (Week 6):
- Score: 100/100
- All patterns from golden standard implemented
- Full automation in place
- Zero deviations from golden standard

**Final Import-tree Validation:**
```bash
# After Phase 4 completion
nix eval .#flake.modules --extra-experimental-features pipe-operators --json | jq 'keys' > final-modules.json
diff initial-modules.json final-modules.json
# Should show only expected additions/changes
```

---

## Risk Mitigation

### Potential Blockers:
1. **Import-tree compatibility issues**
   - Mitigation: Test each change incrementally with pipe-operators
   - Rollback: `git reset --hard HEAD~1` after any failure

2. **Namespace conflicts during reorganization**
   - Mitigation: Verify against golden standard first
   - Validation: `nix flake check --extra-experimental-features pipe-operators`

3. **Test framework redesign complexity**
   - Mitigation: Study golden standard patterns thoroughly
   - Fallback: Create new check-based tests alongside old ones first

4. **Performance degradation**
   - Mitigation: Measure before/after with `nix eval --trace-verbose`
   - Threshold: No more than 10% increase in evaluation time

5. **Golden standard misalignment**
   - Mitigation: Diff every change against golden standard
   - Resolution: When in doubt, follow golden standard exactly

---

## Implementation Schedule

### Week 1:
- Phase 0: Pre-flight and cleanup
- Phase 1: Critical fixes with golden standard validation

### Week 2:
- Phase 2: High priority fixes (Headers, Test Redesign, Metadata)
- Continuous validation against golden standard

### Week 3:
- Phase 3: Optimization and reorganization
- Performance baseline measurements

### Week 4-5:
- Phase 4: Excellence and advanced patterns
- Final validation and documentation

### Week 6:
- Final testing and documentation
- Celebration of 100/100 achievement

---

## Additional Required Sections

### Handling Existing Shell Scripts
**Time:** 1 day
**Files:** 
- `add-module-headers.sh` - CONSOLIDATE
- `simplify-headers.sh` - REMOVE
- `improved-add-headers.sh` - CONSOLIDATE

**Actions:**
1. Consolidate header scripts into single `header-management.sh`
2. Remove redundant scripts
3. Update remaining scripts to:
   - Include `--extra-experimental-features pipe-operators` in all nix commands
   - Match golden standard patterns
   - Include proper error handling
4. Test consolidated script thoroughly

**New Consolidated Script Structure:**
```bash
#!/usr/bin/env bash
# header-management.sh - Manages module headers per golden standard
set -euo pipefail
export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"
# ... consolidated functionality
```

### Performance Impact Assessment
**Time:** Ongoing throughout implementation

**Metrics to Track:**
```bash
# Before changes (with pipe-operators)
time nix eval .#nixosConfigurations.system76.config.system.build.toplevel \
  --extra-experimental-features pipe-operators --trace-verbose 2>&1 | tee baseline.log

# After each phase
time nix eval .#nixosConfigurations.system76.config.system.build.toplevel \
  --extra-experimental-features pipe-operators --trace-verbose 2>&1 | tee phase-X.log

# Compare and calculate percentage
BASELINE=$(grep "evaluation took" baseline.log | awk '{print $3}')
CURRENT=$(grep "evaluation took" phase-X.log | awk '{print $3}')
echo "Performance change: $(echo "scale=2; ($CURRENT/$BASELINE - 1) * 100" | bc)%"

# Action if >10% degradation:
# 1. Profile specific modules: nix eval .#flake.modules.nixos.X --trace-verbose
# 2. Identify bottlenecks
# 3. Optimize or rollback specific changes
```

### CI/CD Integration
**Time:** 2 days

**GitHub Actions Workflow Example:**
```yaml
name: Dendritic Pattern Compliance
on: [push, pull_request]
jobs:
  compliance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: cachix/install-nix-action@v22
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes pipe-operators
      - name: Check compliance
        run: |
          nix flake check --extra-experimental-features pipe-operators
          ./test-dendritic-compliance.sh
      - name: Compare with golden standard
        run: |
          git clone https://github.com/mightyiam/infra /tmp/golden
          diff -r modules /tmp/golden/modules || true
```

**Pre-commit Hook:**
```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit
export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"
nix flake check || exit 1
grep -r "desktop" modules/ --include="*.nix" && echo "Forbidden namespace!" && exit 1
```

---

## Continuous Improvement

### Post-100/100:
1. Automated compliance monitoring with golden standard sync
2. Regular pattern reviews (monthly)
3. Contribution guidelines matching golden standard
4. Knowledge sharing documentation
5. Performance optimization cycles
6. Regular updates from golden standard repository

---

## Golden Standard Synchronization

### Regular Sync Process:
```bash
# Weekly check for golden standard updates
cd /home/vx/git/infra && git pull

# Document any conflicts
git log --oneline -n 10 > golden-updates.log

# Compare patterns with conflict resolution
diff -r /home/vx/nixos/modules /home/vx/git/infra/modules > pattern-diff.txt || true

# If conflicts:
# 1. Document divergence reason in DIVERGENCE.md
# 2. Test both patterns
# 3. Choose pattern that maintains 100/100 score
# 4. Update documentation

# Validate after sync
nix flake check --extra-experimental-features pipe-operators
./test-dendritic-compliance.sh
```

---

## Troubleshooting Guide

### Common Issues and Solutions

**Issue: Infinite recursion during evaluation**
```bash
# Debug with:
nix eval .#flake.modules.nixos --extra-experimental-features pipe-operators --show-trace
# Solution: Check for circular dependencies in namespace references
```

**Issue: Module not found after reorganization**
```bash
# Verify import-tree is working:
nix eval .#flake.modules --extra-experimental-features pipe-operators --json | jq 'keys'
# Solution: Ensure .nix extension and proper location
```

**Issue: Performance degradation >10%**
```bash
# Profile specific modules:
nix eval .#flake.modules.nixos.base --extra-experimental-features pipe-operators --trace-verbose
# Solution: Optimize or rollback specific changes
```

### Debug Commands
```bash
# Show all available modules
nix eval .#flake.modules --extra-experimental-features pipe-operators --json | jq

# Test specific module
nix eval .#flake.modules.nixos.base --extra-experimental-features pipe-operators

# Check for namespace conflicts
nix eval .#nixosConfigurations.system76.config --extra-experimental-features pipe-operators --show-trace 2>&1 | grep "error:"
```

---

## Complete File Lists for Known Issues

### Files with Library Prefix Issues
```bash
# Find all files needing lib. prefix fixes:
grep -l "\\bmap\\b" modules/**/*.nix | xargs grep -L "lib\\.map"
grep -l "\\bfilter\\b" modules/**/*.nix | xargs grep -L "lib\\.filter"
grep -l "\\bmkIf\\b" modules/**/*.nix | xargs grep -L "lib\\.mkIf"

# Currently known:
- modules/storage/storage-redundancy.nix
# Add others as discovered
```

### Files with Hardcoded Values
```bash
# Generate complete list:
grep -l '"vx"' modules/**/*.nix > hardcoded-username.txt
grep -l '"Asia/Riyadh"' modules/**/*.nix > hardcoded-timezone.txt
grep -l "6234" modules/**/*.nix > hardcoded-sshport.txt
```

### Test Files Needing Redesign
- modules/meta/module-tests.nix (primary)
- modules/meta/integration-tests.nix
- Any files with `testModule` function calls

---

## Success Celebration and Verification

### Verification of 100/100 Achievement
```bash
# Final compliance check
./test-dendritic-compliance.sh | grep "Score: 100/100"

# Verify all patterns match golden standard
diff -r modules /home/vx/git/infra/modules

# Run comprehensive validation
nix flake check --extra-experimental-features pipe-operators
nix build .#nixosConfigurations.system76.config.system.build.toplevel --extra-experimental-features pipe-operators

# Generate final QA report
./generate-qa-report.sh > FINAL_QA_REPORT.md
```

### Documentation of Journey
1. Create blog post about the migration
2. Update README with achievement badge
3. Create case study for Dendritic Pattern adoption

### Sharing with Community
```bash
# Create PR to share improvements back
git checkout -b dendritic-100
git push origin dendritic-100
# Open PR with detailed description of journey
```

### Success Metrics Archive
```bash
# Archive all metrics for future reference
mkdir -p achievement-100
cp QA_REPORT.md achievement-100/
cp DENDRITIC_ACTION_PLAN.md achievement-100/
cp baseline.log phase-*.log achievement-100/
tar -czf dendritic-100-achievement.tar.gz achievement-100/
```

---

*This action plan Version 3.0 addresses every issue identified in the QA Report and review feedback with specific, measurable, and time-bound actions to achieve perfect Dendritic Pattern compliance.*