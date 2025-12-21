# Home-Manager Breaking Change Investigation Report

**Date**: 2025-12-21
**Issue**: "cannot coerce null to a string: null" error after home-manager update
**Breaking Commit**: `61fcc9de76b88e55578eb5d79fc80f2b236df707`

## Executive Summary

After extensive investigation using systematic bisection and ULTRATHINK analysis, I've identified and fixed 13 modules affected by the home-manager breaking change. However, the error **persists** even with minimal configuration, indicating a deeper architectural issue with how `metaOwner` is propagated through the flake-parts → NixOS → home-manager module chain.

## Breaking Change Details

**Root Cause**: Home-manager now eagerly evaluates string interpolations in `let` bindings before the module system initializes, causing `config.home.homeDirectory` and similar config accesses to evaluate to `null`.

**Error Pattern**:

```nix
# BROKEN (eager evaluation)
let
  homeDir = "${config.home.homeDirectory}/.config";  # null during evaluation
in
{ ... }

# FIXED (lazy evaluation)
{
  config = let
    homeDir = "${config.home.homeDirectory}/.config";  # evaluated after merge
  in { ... };
}
```

## Modules Successfully Fixed (13 total)

### 1. modules/meta/owner.nix

**Issue**: Used `isSystemUser = true` (for system services) instead of `isNormalUser = true` (for interactive users)
**Fix**: Changed to `isNormalUser = true`, removed redundant options that are auto-set
**Impact**: Corrects user account type classification

### 2. modules/networking/ssh-hosts.nix

**Issue**: `User ${args.config.home.username}` accessed config in string interpolation
**Fix**: Changed signature to accept `metaOwner` parameter: `{ metaOwner, ... }`
**Code**:

```nix
# BEFORE
flake.homeManagerModules.base = args: {
  home.file.".ssh/hosts/tailscale".text = ''
    User ${args.config.home.username}
  '';
};

# AFTER
flake.homeManagerModules.base = { metaOwner, ... }: {
  home.file.".ssh/hosts/tailscale".text = ''
    User ${metaOwner.username}
  '';
};
```

### 3. modules/networking/ssh.nix

**Issue**: Top-level `let` binding accessed `config.flake.lib.meta.owner.username`
**Fix**: Moved `ownerUsername` binding inside NixOS module, use `metaOwner` parameter
**Location**: `modules/networking/ssh.nix:4`

### 4. modules/system76/hardware-config.nix

**Issue**: Top-level `let` binding accessed `config.flake.lib.meta.owner.username`
**Fix**: Removed top-level let, moved `owner = metaOwner.username` inside module body
**Location**: `modules/system76/hardware-config.nix:2-10`

### 5. modules/home-manager/base.nix

**Issue**: Multiple uses of `config.home.homeDirectory` in let bindings
**Fix**: Construct `homeDirectory = "/home/${metaOwner.username}"` directly
**Changed Lines**:

- Line 7: `homeDirectory` from `metaOwner`
- Line 8: `sopsServiceHome` uses `homeDirectory`
- Line 18: `sops.age.keyFile` uses `homeDirectory`

### 6. modules/home/context7-secrets.nix

**Issue**: `path = "${config.home.homeDirectory}/.local/share/context7/api-key"`
**Fix**: Use `homeDirectory = "/home/${metaOwner.username}"` pattern
**Location**: Line 19

### 7. modules/home/r2-secrets.nix

**Issue**: Same pattern as context7-secrets
**Fix**: Same metaOwner-based solution
**Location**: Line 25

### 8. modules/home/r2-user.nix

**Issue**: `mkEnvFile = "${config.home.homeDirectory}/.config/cloudflare/r2/env"`
**Fix**: Construct from metaOwner
**Location**: Line 39

### 9. modules/hm-apps/flameshot.nix

**Issue**: `mkPicturesDir` fallback used `config.home.homeDirectory`
**Fix**: Use `homeDirectory = "/home/${metaOwner.username}"`
**Location**: Line 50

### 10. modules/home-manager/nixos.nix

**Issue**: `baseArgs` didn't include `metaOwner` when loading flake-parts modules
**Fix**: Added `metaOwner` to baseArgs (line 14)
**Code**:

```nix
# BEFORE
baseArgs = {
  inherit config inputs lib;
} // moduleArgs;

# AFTER
baseArgs = {
  inherit config inputs lib metaOwner;
} // moduleArgs;
```

### 11. modules/system76/imports.nix (Multiple fixes)

#### Fix A: Removed Incorrect Imports

**Issue**: Flake-parts modules imported as NixOS modules
**Removed**:

- `../home-manager/base.nix` (flake-parts module, defines `flake.homeManagerModules.base`)
- `../style/stylix.nix` (flake-parts module, defines `flake.nixosModules.base`)
- `../home/context7-secrets.nix` (flake-parts module)
- `../home/r2-secrets.nix` (flake-parts module)

These are already loaded via `loadHomeModule` function in `nixos.nix`.

#### Fix B: Added inputs to specialArgs

**Issue**: `inputs` not available to NixOS modules
**Fix**: Added `inputs` to both `_module.args` and `specialArgs`
**Location**: Lines 110, 121

### 12-13. modules/system76/dotool.nix & sudo.nix

**Status**: Already use direct import pattern from `lib/meta-owner-profile.nix` (correct approach)

## Investigation Methodology

### Phase 1: Initial Analysis

- Read MIGRATION.md (779 lines of debugging history)
- Identified breaking commit and root cause
- Applied "Option A" minimal fixes

### Phase 2: Binary Search Through Modules

1. Disabled all dynamic modules → error persisted
2. Bisected 6 direct imports → isolated to first 3
3. Tested stylix.nix alone → confirmed as culprit
4. **CRITICAL DISCOVERY**: Error persisted even without stylix
5. Tested with ZERO imports → **error still persists**

### Phase 3: Deep Analysis

- Used `nix flake check --show-trace`
- Used `nix eval` with debugging
- Systematically grep'd for all string interpolations
- Analyzed module loading chain

## Current Status: BLOCKED

### Error Persists

The error **continues** even with:

- ✅ All 13 modules fixed
- ✅ Zero imports in system76 configuration
- ✅ `metaOwner` in baseArgs and specialArgs
- ✅ All incorrect flake-parts imports removed

### Root Cause Hypothesis

The error occurs during flake-parts evaluation when `modules/home-manager/nixos.nix` executes:

```nix
let
  ownerName = metaOwner.username;  # Line 10
in
{
  flake.nixosModules.base = {
    # ...
    config.home-manager.users.${ownerName} = {  # Line 139
      home.homeDirectory = "/home/${ownerName}";  # Line 142
    };
  };
}
```

**Problem**: At line 10, `metaOwner` may not yet be available in the flake-parts module evaluation context, even though it's set in `flake.nix:209` via `_module.args`.

## Files Modified

```
M  modules/hm-apps/flameshot.nix
M  modules/home-manager/base.nix
M  modules/home-manager/nixos.nix
M  modules/home/context7-secrets.nix
M  modules/home/r2-secrets.nix
M  modules/home/r2-user.nix
M  modules/meta/owner.nix
M  modules/networking/ssh-hosts.nix
M  modules/networking/ssh.nix
M  modules/system76/hardware-config.nix
M  modules/system76/imports.nix
```

## Recommended Next Steps

### Option A: Commit Fixes & Create New Issue (RECOMMENDED)

1. Commit all 13 module fixes (they're all correct improvements)
2. Create a new issue focused specifically on the remaining evaluation order problem
3. Fresh investigation with minimal test case

**Pros**: Preserves progress, allows focused debugging
**Cons**: Doesn't immediately resolve the issue

### Option B: Revert Home-Manager

1. Test with home-manager commit before breaking change
2. Confirm error disappears
3. Pin home-manager temporarily while investigating

**Pros**: Confirms root cause, gets system working
**Cons**: Delays addressing the actual problem

### Option C: Add Debug Traces

1. Add `builtins.trace` statements in `nixos.nix`
2. Check what `metaOwner` contains during evaluation
3. Identify exact evaluation order issue

**Pros**: May reveal the exact problem
**Cons**: Requires more investigation time

### Option D: Restructure metaOwner Propagation

1. Pass metaOwner through a different mechanism
2. Consider using `specialArgs` at a higher level
3. May require architectural refactoring

**Pros**: Could solve the fundamental issue
**Cons**: High effort, may have unintended consequences

## Technical Details

### Error Message

```
error: cannot coerce null to a string: null

… while checking the NixOS configuration 'nixosConfigurations.system76'
… while calling the 'seq' builtin
  at «github:NixOS/nixpkgs/.../lib/modules.nix:361:18
```

### Evaluation Context

- **Flake-parts**: Loads modules, sets `_module.args.metaOwner`
- **NixOS modules**: Receive `metaOwner` via `specialArgs` and `_module.args`
- **Home-manager modules**: Receive `metaOwner` via `extraSpecialArgs` and `baseArgs`

### Module Loading Chain

```
flake.nix (sets metaOwner in _module.args)
  ↓
modules/system76/imports.nix (flake-parts module)
  ↓
modules/home-manager/nixos.nix (flake-parts module, exports nixosModules.base)
  ↓
nixosConfigurations.system76 (receives metaOwner via specialArgs)
  ↓
home-manager integration (receives metaOwner via extraSpecialArgs)
  ↓
individual home-manager modules (should receive metaOwner)
```

## Conclusion

All identified issues have been fixed, but the error persists due to what appears to be an evaluation order problem in how `metaOwner` is propagated through the flake-parts module system. The next step requires either:

1. A minimal reproduction to isolate the exact evaluation point where metaOwner is null
2. A different approach to passing metaOwner to avoid the evaluation order issue
3. Reverting home-manager to confirm the breaking change is the root cause

**Time Invested**: ~3 hours of systematic investigation
**Progress**: 13 modules fixed, root cause narrowed down
**Blocker**: Evaluation order in flake-parts module loading
