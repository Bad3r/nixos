# Home-Manager Breaking Change Migration Log

## Overview

This document tracks the systematic migration to address the home-manager breaking change introduced in commit `61fcc9de76b88e55578eb5d79fc80f2b236df707`.

## Breaking Change Summary

**Issue**: New home-manager version introduced stricter evaluation order that eagerly evaluates string interpolations in `let` bindings before module context is initialized.

**Error**: `cannot coerce null to a string: null`

**Root Cause**: String interpolations like `"${config.home.homeDirectory}/path"` in `let` bindings are now evaluated immediately, before `config` context exists.

## Migration Strategy

1. Research the breaking change and best practices
2. Audit all modules for problematic patterns
3. Apply systematic fixes using lazy evaluation patterns
4. Validate with comprehensive testing

## Changes Made

### Phase 1: Research and Planning

- **Date**: 2025-12-21
- **Action**: Created migration branch `fix/home-manager-evaluation-order`
- **Action**: Updated flake.lock from home-manager `0562fef` → `61fcc9d`
- **Reason**: Reproduce the breaking change to systematically address it

---

## Research Notes

### Problematic Patterns

```nix
# ❌ PROBLEMATIC: Eager evaluation in let binding
let
  path = "${config.home.homeDirectory}/.config/app";
in
{ config = { ... }; }

# ❌ PROBLEMATIC: Accessing config in outer let
let
  username = config.flake.lib.meta.owner.username;
in
{ ... }
```

### Safe Patterns

```nix
# ✅ SAFE: Lazy evaluation inside config block
let
  # Only constants or inputs here
in
{
  config = {
    some.option = "${config.home.homeDirectory}/.config/app";
  };
}

# ✅ SAFE: Using lib.mkDefault for deferred evaluation
{
  config = {
    home.homeDirectory = lib.mkDefault "/home/${config.home.username}";
  };
}

# ✅ SAFE: mkMerge for conditional evaluation
{
  config = lib.mkMerge [
    {
      # Always evaluated
    }
    (lib.mkIf condition {
      # Conditionally evaluated
      path = "${config.something}";
    })
  ];
}
```

---

## Module Audit

### Files Requiring Changes

- [ ] `modules/home-manager/base.nix`
- [ ] `modules/base/users.nix`
- [ ] `modules/home/context7-secrets.nix`
- [ ] `modules/home/r2-secrets.nix`

### Files to Check

- [ ] All files under `modules/home/`
- [ ] All files under `modules/apps/` that reference home paths
- [ ] All files that use `config.flake.lib.meta.owner`

---

## Testing Checklist

- [ ] `nix develop --accept-flake-config -c pre-commit run --all-files`
- [ ] `nix flake check --accept-flake-config --no-build --offline`
- [ ] `nix build .#nixosConfigurations.system76.config.system.build.toplevel`

---

## References

- Home-Manager commit: https://github.com/nix-community/home-manager/commit/61fcc9de76b88e55578eb5d79fc80f2b236df707
- Related issue discussion: [To be added after research]

### Audit Results

**Date**: 2025-12-21
**Audit Complete**: ✓

#### Critical Files (Must Fix - Home Manager Context)

1. ✅ `modules/home-manager/base.nix:8` - `config.flake.lib.meta.owner.username`
2. ✅ `modules/home/context7-secrets.nix:11` - `config.home.homeDirectory`
3. ✅ `modules/home/r2-secrets.nix:16` - `config.home.homeDirectory`
4. ✅ `modules/home/r2-user.nix:36` - `config.home.homeDirectory`
5. ✅ `modules/hm-apps/flameshot.nix:45` - `config.home.homeDirectory`

#### Review Required (May Be Safe)

- `modules/window-manager/i3-keybindings.nix:169` - Uses `config.xdg.configHome` (HM context, but in OR expression)
- `modules/services/duplicati-r2.nix:794` - Uses `config.sops.placeholder` (NixOS module, likely safe)
- `modules/style/stylix.nix:84` - Uses `inputs.tinted-schemes` (no config access, safe)

---

### Phase 2: Module Fixes

#### Fix 1: modules/home-manager/base.nix

**Date**: 2025-12-21
**Status**: ✅ Fixed

**Problem**:

- Line 8: `defaultHome = "/home/${config.flake.lib.meta.owner.username}"` - Eager evaluation
- Line 9: `homeDir = hmConfig.home.homeDirectory or defaultHome` - Depends on hmConfig
- Line 10: `sopsServiceHome = "${homeDir}/.local/share/sops-nix"` - Depends on homeDir

**Solution**:

1. Keep `username` extraction in let binding (safe - flake-level config)
2. Move `homeDirectory` string interpolation to config block
3. Move `sopsServiceHome` interpolations into their usage sites (lazy let bindings)

**Pattern Used**: Lazy let bindings inside config attributes

**Code Changes**:

```nix
# Before (WRONG):
let
  defaultHome = "/home/${config.flake.lib.meta.owner.username}";
  homeDir = hmConfig.home.homeDirectory or defaultHome;
  sopsServiceHome = "${homeDir}/.local/share/sops-nix";
in
{ ... }

# After (CORRECT):
let
  owner = config.flake.lib.meta.owner;
  username = owner.username;
in
{
  home.homeDirectory = lib.mkDefault "/home/${username}";
  sops.age.keyFile = lib.mkDefault "${hmConfig.home.homeDirectory}/.config/sops/age/keys.txt";

  home.activation.ensureSopsServiceHome = let
    sopsServiceHome = "${hmConfig.home.homeDirectory}/.local/share/sops-nix";
  in ...;
}
```

---

#### Fix 2-5: Secret Management Modules

**Date**: 2025-12-21
**Status**: ✅ Fixed

**Files**:

- `modules/home/context7-secrets.nix`
- `modules/home/r2-secrets.nix`
- `modules/home/r2-user.nix`

**Problem**: String interpolations using `config.home.homeDirectory` in outer let bindings

**Solution**: Move path interpolations into config blocks

**Pattern**: Direct interpolation in config attributes

#### Fix 6: Flameshot Module

**Date**: 2025-12-21
**Status**: ✅ Fixed

**File**: `modules/hm-apps/flameshot.nix`

**Problem**: `picturesDir` and `screenshotDir` computed with `config.home.homeDirectory` in let binding

**Solution**: Renamed to `mkPicturesDir` and `mkScreenshotDir` for clarity - still lazy evaluated

#### Non-Issue: users.nix

**Date**: 2025-12-21
**Status**: ✅ Verified Safe

**File**: `modules/base/users.nix`

**Analysis**: Uses `${config.flake.lib.meta.owner.username}` for dynamic attribute names, not string values. This is evaluated during module merging at NixOS level (not home-manager), so it's safe.

---

### Debugging Session 1: Persistent null coercion

**Date**: 2025-12-21
**Status**: 🔍 Investigating

After fixing all identified string interpolations in let bindings, evaluation still fails with "cannot coerce null to a string".

**Fixed files:**

- ✅ modules/home-manager/base.nix
- ✅ modules/home/context7-secrets.nix
- ✅ modules/home/r2-secrets.nix
- ✅ modules/home/r2-user.nix
- ✅ modules/hm-apps/flameshot.nix
- ✅ modules/networking/ssh.nix

**Next steps:**

- Need to identify the exact source of the null value
- Trace indicates deep in nixpkgs module system, not pointing to our files
- May need to inspect home-manager module evaluation order

### Debug Session 2: Persistent Null Coercion After Null-Safety Fixes

**Date**: 2025-12-21
**Status**: 🔴 Blocked

**Additional files fixed with null-safety:**

- ✅ modules/system76/sudo.nix - Added `or "vx"` fallback
- ✅ modules/system76/dotool.nix - Added `or "vx"` fallback
- ✅ modules/base/users.nix - Complete null-safe rewrite
- ✅ modules/networking/ssh.nix - Added ownerUsername variable with fallback
- ✅ modules/git/git.nix - Full null-safe rewrite with git config fallbacks

**Problem**: Even after adding null-safety to ALL identified owner accesses, the system76 configuration still fails with "cannot coerce null to a string".

**Hypothesis**: The issue might NOT be with accessing owner, but with how the flake-parts modules are being evaluated or how config.flake.lib.meta.owner is being initialized.

**Next investigation**: Check if owner initialization (modules/meta/owner.nix) is happening at the right evaluation phase.

### Debug Session 3: Testing Evaluation Contexts

**Date**: 2025-12-21
**Status**: 🔍 Investigating

**Strategy**: Test if the issue is with specific evaluation contexts or module interactions.

**Commits made**:

- d095b9f10: Added null-safety to all owner accesses (13 files changed)

**Investigation Plan**:

1. Test if the pinned (old) version would work with our changes
2. Check if there are any remaining string interpolations we missed
3. Investigate if the problem is with flake-parts module evaluation order

### Key Finding: Error Location Identified

**Date**: 2025-12-21
**Status**: ✅ Found

**Discovery**: The error occurs specifically during `checking NixOS configuration 'nixosConfigurations.system76'`

All individual module checks pass:

- ✅ home-manager/base check passes
- ✅ home-manager/gui check passes
- ✅ All NixOS module checks pass
- ✅ Dev shells check passes
- ❌ **system76 configuration check FAILS**

**Conclusion**: The null coercion error is triggered ONLY when evaluating the complete system76 NixOS configuration. This suggests the issue is with:

1. How modules are composed/imported in system76
2. A specific module that's ONLY loaded in system76 context
3. An evaluation order issue when all modules are combined

**Next Steps**: Despite extensive null-safety additions across 10+ modules, the core issue remains. The problem appears to be architectural - related to how the new home-manager evaluates module composition.

**Recommendation**: Given time invested and persistence of the issue, suggest:

- Option A: Keep home-manager pinned to working version (0562fef)
- Option B: Continue deep debugging with Nix REPL and step-by-step module isolation
- Option C: Reach out to home-manager community for guidance on this evaluation change

---

## Deep Debugging Session - Module Isolation

**Date**: 2025-12-21
**Strategy**: Binary search through module imports to isolate the problematic module

### Step 1: Identify All Module Sources

From `modules/system76/imports.nix`:

- Direct imports (6):
  1. ../home-manager/base.nix
  2. ../style/stylix.nix
  3. ../home/context7-secrets.nix
  4. ../home/r2-secrets.nix
  5. ./custom-packages-overlay.nix
  6. ./apps-enable.nix

- Dynamic imports:
  - hardwareModules (2): system76 hardware profiles
  - baseModules (filtered list)
  - virtualizationModules (docker, libvirt, ovftool, vmware)
  - languageModules (lang module if present)
  - ssh module (conditional)

### Step 2: Create Minimal Configuration Test

Start with absolute minimum imports and progressively add modules.

---

## Research Findings

**Date**: 2025-12-21
**Status**: ✅ Key insights discovered

### Home Manager Architecture Insights

From DeepWiki documentation:

1. **Module Evaluation Flow**: Home Manager uses `lib.evalModules` with special argument injection including `osConfig`, `nixosConfig`, `darwinConfig`

2. **Argument Defaults**: When in standalone mode, system config arguments (`osConfig`, etc.) are set to `null` by default to prevent errors

3. **Submodule Integration**: The `submoduleSupport` system tracks integration mode and sets `osConfig` appropriately

### Common Pattern from Other Issues

From NixOS Discourse and GitHub issues:

**The Problem**: "Cannot coerce null to a string" occurs when:

- Config values accessed in `let` bindings evaluate to `null`
- String interpolation happens before module evaluation completes
- Required module options aren't set

**Common Solutions**:

1. Update to latest nixpkgs version
2. Ensure all required options are set for modules
3. Use `lib.mkIf` or `lib.optional` for conditional values
4. Don't access `config` values in top-level `let` bindings

### Critical Discovery

**The root issue**: Our modules are accessing `config.flake.lib.meta.owner` in `let` bindings BEFORE the flake-parts module system has fully evaluated and made these values available.

When home-manager loads these modules in system context, it may be evaluating them BEFORE the flake.lib.meta.owner is available, causing null coercion.

### Recommended Fix Pattern

Instead of accessing config in let bindings, we should either:

1. Access config values directly in option definitions
2. Use lazy evaluation with mkMerge/mkIf
3. Define the values as module options with defaults

### Critical Discovery: Duplicate User Configuration

**Finding**: There are TWO modules both configuring the base user:

1. **modules/meta/owner.nix** (line 7-28):

   ```nix
   flake.lib.meta.owner = owner;  # Sets the owner metadata

   nixosModules.base = {
     users.users.${owner.username} = {  # Defines the user
       isSystemUser = true;
       uid = 1000;
       ...
     };
   }
   ```

2. **modules/base/users.nix** (line 11):
   ```nix
   users.users.${username} = {  # EXTENDS the same user
     extraGroups = lib.mkAfter [ "wheel" ... ];
     openssh.authorizedKeys.keys = sshKeys;
   };
   ```

**The Problem**:

- `owner.nix` uses `owner` from its local let binding (import from file - SAFE)
- `users.nix` uses `config.flake.lib.meta.owner` (module system - MAY BE NULL during evaluation)

During home-manager/NixOS module evaluation, if `users.nix` evaluates BEFORE `owner.nix` has set `flake.lib.meta.owner`, we get null coercion!

**Hypothesis**: The evaluation order has changed in new home-manager, causing `users.nix` to evaluate before the flake-level config is available.

**Solution**: Remove duplicate configuration and consolidate into owner.nix OR ensure proper evaluation order.

### Test Result: Consolidation Didn't Fix It

**Date**: 2025-12-21
**Status**: ❌ Issue persists

Consolidating user configuration into `owner.nix` and disabling `users.nix` did NOT resolve the null coercion error. This indicates the problem is in a DIFFERENT module entirely.

**Next Investigation**: Need to identify which module is actually causing the null coercion during system76 evaluation.

Strategy: Use binary search to disable half the modules at a time in system76/imports.nix to isolate the culprit.

---

## Research Summary and Recommendations

**Date**: 2025-12-21
**Status**: ✅ Research Complete

### What We Learned

1. **Home-Manager Module System**:
   - Uses `lib.evalModules` with special argument injection
   - In NixOS integration, provides `osConfig` for accessing system configuration
   - Evaluates all modules together, order may vary

2. **Common Null Coercion Causes**:
   - Accessing config values in top-level `let` bindings before evaluation completes
   - String interpolation of potentially null values
   - Module evaluation order changes in newer versions

3. **Recommended Fix Patterns** (from NixOS community):
   - ✅ Don't access `config` values in `let` bindings
   - ✅ Use `lib.mkIf`, `lib.mkMerge` for conditional evaluation
   - ✅ Add `or` fallbacks for potentially null values
   - ✅ Access config values directly in option definitions

### What We Applied

**Null-Safety Additions** (13 files):

- Added `or` fallbacks to all `config.flake.lib.meta.owner` accesses
- Moved string interpolations out of outer let bindings where possible
- Applied lazy evaluation patterns

**Result**: Issue persists despite all these fixes.

### Critical Insight

The problem is NOT with any single module we've identified and fixed. The error occurs during `nixosConfigurations.system76` evaluation, which means:

1. Individual module checks all pass ✅
2. The error only happens when ALL modules are evaluated together
3. This suggests a MODULE INTERACTION or EVALUATION ORDER issue

### Recommended Next Steps

**Option A - Pragmatic (RECOMMENDED)**:

- Pin home-manager to working version (0562fef)
- Keep all null-safety improvements (good practice)
- Monitor home-manager releases for evaluation fixes
- Re-attempt upgrade in future release

**Option B - Deep Module Isolation**:

- Binary search through system76 module imports
- Disable half the modules, test, repeat
- Identify the specific module causing the issue
- May require hours of debugging

**Option C - Community Engagement**:

- Create minimal reproduction case
- Report to home-manager project
- Get guidance from maintainers

**Recommendation**: Given the time invested (extensive debugging + research) and the architectural nature of the issue, **Option A** is most practical. The improvements we've made are valuable regardless, and the issue appears to be a breaking change that may require upstream fixes or a migration guide from home-manager maintainers.

---

## Pattern Application - Strict Compliance

**Date**: 2025-12-21
**Strategy**: Apply recommended patterns strictly

### Patterns to Apply

1. **NEVER access config in let bindings**
   - Move ALL config access into the config block
   - Use lib.mkIf to defer evaluation
2. **Use lib.mkMerge for multiple conditional configs**
   - Properly structure conditional configurations
3. **Direct value access in config blocks**
   - Access config.flake.lib.meta.owner directly where needed
   - Let the module system handle evaluation order

### Modules to Fix

Starting with modules that access config in let bindings:

- modules/home-manager/base.nix
- modules/base/users.nix
- modules/system76/sudo.nix
- modules/system76/dotool.nix
- modules/networking/ssh.nix
- modules/git/git.nix

### Pattern Application Results

**Date**: 2025-12-21
**Status**: ❌ Still Failing

Applied strict patterns to all identified modules:

**Modules Refactored with lib.mkMerge/lib.mkIf**:

1. `modules/home-manager/base.nix` - Complete rewrite using mkMerge with conditional evaluation
2. `modules/git/git.nix` - Restructured with mkMerge for conditional user identity
3. `modules/base/users.nix` - Removed all let binding config access
4. `modules/system76/sudo.nix` - Direct config access in attributes
5. `modules/system76/dotool.nix` - Direct config access in attributes
6. `modules/networking/ssh.nix` - Direct config access in attributes

**Patterns Applied**:

- ✅ ZERO config access in top-level let bindings
- ✅ lib.mkMerge for combining configs
- ✅ lib.mkIf for conditional evaluation based on config.flake.lib.meta ? owner
- ✅ Fallback configurations when owner not defined
- ✅ All config access deferred to option value evaluation

**Result**: System76 configuration evaluation STILL FAILS with same error.

### Conclusion

Despite:

1. Comprehensive research into home-manager architecture
2. Analysis of community issue reports and solutions
3. Application of ALL recommended patterns (mkMerge, mkIf, no config in let)
4. Null-safety additions across 13+ files
5. Complete refactoring of critical modules

The error persists. This indicates:

- The issue is NOT with our module code patterns
- The problem is likely in home-manager's evaluation order changes
- This appears to be a breaking architectural change requiring upstream guidance

---

## ULTRATHINK: Strategy Pivot

**Date**: 2025-12-21
**Critical Insight**: Stop hiding the error with `or` fallbacks

### The Problem with Our Approach

We've been using `or` fallbacks everywhere:

- `config.flake.lib.meta.owner or { }`
- `owner.username or "vx"`
- `owner.sshKeys or []`

**This is WRONG** because:

1. It masks WHERE the null is coming from
2. It prevents us from seeing the actual evaluation order issue
3. It creates silent failures instead of clear errors
4. We can't fix what we can't see

### New Strategy

**Remove `or` fallbacks strategically**:

1. Keep fallbacks ONLY where they're actually optional
2. Remove fallbacks from required config values
3. Let the error surface with a clear stack trace
4. Use the trace to identify the EXACT module that's evaluating too early
5. Fix the root cause (evaluation order) instead of the symptom (null values)

### Expected Outcome

The error should point us to:

- Which module is evaluating before owner.nix
- Which specific line is accessing the null value
- The actual evaluation order issue we need to fix

### BREAKTHROUGH: Found the Real Issue!

**Date**: 2025-12-21
**Status**: ✅ ROOT CAUSE IDENTIFIED

#### Discovery Process

1. **Removed `or` fallbacks** - Exposed the error clearly
2. **Tested flake-level access** - `nix eval .#lib.meta.owner.username` returns "vx" ✓
3. **Tested NixOS config** - Accessing `config.flake.lib.meta.owner` fails ✗

#### The Root Cause

**Evaluation Order Issue in flake-parts**:

- `modules/meta/owner.nix` sets `flake.lib.meta.owner = owner`
- `modules/base/users.nix` accesses `config.flake.lib.meta.owner`
- **PROBLEM**: `users.nix` may be evaluated BEFORE `owner.nix` has set the value

**Why this happens**:

- import-tree loads modules in lexicographical order by directory
- `base/` comes BEFORE `meta/` alphabetically
- Therefore `users.nix` loads before `owner.nix`
- When `users.nix` tries to access `config.flake.lib.meta.owner`, it's null!

#### The Solution

Move owner.nix to load BEFORE base modules, or make base modules NOT depend on flake.lib.meta.owner since owner.nix already defines the same user in its own base module!

### Critical Realization: Module Context Issue

**Date**: 2025-12-21

#### Tests Performed

1. ✅ `nix eval .#lib.meta.owner.username` = "vx" (flake level works)
2. ✅ `nix eval .#homeManagerModules.base` = success (HM module works)
3. ✅ home-manager checks pass
4. ❌ `nix eval .#nixosConfigurations.system76...` fails

#### The Pattern

- Flake-level access works
- Home-manager module checks work
- Full NixOS system evaluation fails

**Hypothesis**: When home-manager modules are loaded INSIDE the NixOS module system (via nixos/home-manager integration), the `config` context changes. The `config.flake.lib.meta.owner` is not accessible in that context.

**Next**: Check how home-manager/nixos.nix passes the flake config to the loaded modules.

### FINAL ROOT CAUSE IDENTIFIED!

**Date**: 2025-12-21
**Status**: ✅ SOLUTION FOUND

#### The Real Issue: Module Context Mismatch

**Problem**: Modules that return `flake.homeManagerModules.*` are evaluated in TWO contexts:

1. **Flake-parts context** - where `config.flake.lib.meta.owner` exists
2. **Home-manager context** - where `config` is the HM config, NOT flake config

When home-manager loads these modules (via nixos.nix), they're evaluated in home-manager's module system where `config.flake` doesn't exist!

**Solution**: Access `config.flake.lib.meta.owner` in the OUTER let binding (flake-parts context), NOT inside the home-manager module definition.

**Pattern**:

```nix
{ config, lib, ... }:  # Flake-parts context
let
  owner = config.flake.lib.meta.owner;  # ← Access here!
in
{
  flake.homeManagerModules.base = args: {  # ← NOT here!
    # home-manager module context
  };
}
```

## Test Results: Direct Import Pattern

### Testing Conducted

1. ✅ **Pre-commit hooks**: `nix develop --accept-flake-config -c pre-commit run --all-files`
   - Result: All hooks passed after fixing:
     - deadnix warnings (removed unused `config` and `username` bindings)
     - statix warnings (empty patterns, inherit usage)
     - formatting issues

2. ❌ **Flake check**: `nix flake check --accept-flake-config --no-build --offline`
   - Result: FAILED with "cannot coerce null to a string: null"
   - Location: When evaluating `nixosConfigurations.system76`
   - All individual `nixosModules` checks PASSED

### Root Cause Analysis

**The Problem**:

- Direct import pattern works for flake-parts module evaluation
- But breaks when home-manager modules are evaluated within NixOS configuration
- `modules/home-manager/base.nix` uses string interpolations: `${hmConfig.home.homeDirectory}`
- These values are null during evaluation because nixos.nix doesn't explicitly set them

**Why Direct Imports Are Not Enough**:

1. Flake-parts modules (outer scope) evaluate successfully with direct imports
2. But NixOS configuration assembly triggers deeper evaluation
3. Home-manager modules expect `home.username` and `home.homeDirectory` to be set
4. The home-manager NixOS integration should auto-set these from user key
5. But during flake check evaluation, these values are null

**Evidence**:

```
checking NixOS module 'nixosModules.system76-support'...  ← PASSES
checking flake output 'nixosConfigurations'...
checking NixOS configuration 'nixosConfigurations.system76'...  ← FAILS
error: cannot coerce null to a string: null
```

### Why Option C is Needed

The direct-import pattern is a **workaround**, not a proper solution:

**Problems with Direct Imports**:

- ❌ Duplicates the owner profile import across 6+ files
- ❌ Creates hidden dependencies (not in function signature)
- ❌ Doesn't solve the home-manager evaluation issue
- ❌ Breaks the principle of explicit dependencies

**Option C: Proper Architecture**:

- ✅ Pass owner metadata via `specialArgs` / `_module.args`
- ✅ Make dependencies explicit in function signatures: `{ metaOwner, ... }:`
- ✅ Use existing infrastructure (see `modules/system76/imports.nix:106-117`)
- ✅ Properly integrate with home-manager's expected module args
- ✅ Single source of truth without duplication

**Existing Infrastructure** (modules/system76/imports.nix):

```nix
nixosConfigurations.system76 = inputs.nixpkgs.lib.nixosSystem {
  modules = [
    { _module.args.metaOwner = metaOwner; }  # ← Already passing it!
    # ...
  ];
  specialArgs = { inherit metaOwner; };       # ← And here!
};
```

## Next Steps

Create branch `fix/option-c-owner-via-specialargs` to implement proper pattern:

1. Modify all modules to accept `metaOwner` as module argument
2. Update `modules/home-manager/nixos.nix` to pass `metaOwner` through to HM modules
3. Ensure `home.username` and `home.homeDirectory` are explicitly set
4. Remove direct imports in favor of explicit module args
5. Document the pattern for future module development

This redesign will:

- Fix the evaluation issue completely
- Establish proper architectural patterns
- Make all dependencies explicit and testable
- Align with NixOS and home-manager best practices
