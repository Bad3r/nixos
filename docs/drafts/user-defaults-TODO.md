# User Defaults Implementation Checklist

> **Status:** In Progress
> **Plan Reference:** [`user-defaults-implementation-plan.md`](./user-defaults-implementation-plan.md)
> **Last Updated:** 2026-01-12

---

## Phase 0: Preparation

### 0.1 Codebase Analysis

- [ ] Review current `i3-config.nix` structure (lines 241-252 for `commandsDefault`, lines 652-656 for `assigns`)
- [ ] Document all hardcoded package references to migrate:
  - [ ] `pkgs.kitty` (terminal)
  - [ ] `pkgs.firefox` (browser)
  - [ ] Class patterns: `geany`, `firefox`, `thunar`
- [ ] Confirm Non-Goals: WM-specific commands stay hardcoded (launcher, emoji, playerctl, volume, brightness, screenshot, logseqToggle, powerProfile)

---

## Phase 1: Module Infrastructure

### 1.1 Options Module Scaffolding

Create `modules/meta/user-defaults.nix`:

- [ ] Create file with header documentation (architecture constraint, workflow guide)
- [ ] Define module structure with dendritic export pattern
- [ ] Add `{ config, lib, pkgs, ... }:` function signature

**Verification:**
```bash
nix-instantiate --parse modules/meta/user-defaults.nix
```

### 1.2 App Role Submodule Definition

Inside `userDefaultsModule`, define `appRoleModule`:

- [ ] Add `package` option (`types.package`)
  - [ ] Include description and literalExpression example
- [ ] Add `windowClass` option (`types.str`)
  - [ ] Include description with `xprop WM_CLASS` guidance
- [ ] Add `desktopEntry` option (`types.str`)
  - [ ] Include description for MIME associations
- [ ] Add `appId` option (`types.nullOr types.str`, default `null`)
  - [ ] Include description for Wayland compositors
- [ ] Add `windowClassAliases` option (`types.listOf types.str`, default `[]`)
  - [ ] Include description and example for multi-class apps
- [ ] Add `moduleName` option (`types.nullOr types.str`, default `null`)
  - [ ] Include description for pname != module namespace cases

### 1.3 Top-Level Options

Define `options.userDefaults`:

- [ ] Add `enable` option (`mkEnableOption` with `default = true`)
- [ ] Add `strictValidation` option (`types.bool`, default `false`)
  - [ ] Include description explaining warning vs assertion behavior
- [ ] Add `apps` option (`types.attrsOf (types.submodule appRoleModule)`)
  - [ ] Include description and literalExpression example

### 1.4 Default Configuration Values

In `config = lib.mkIf cfg.enable { ... }`:

- [ ] Add `browser` defaults:
  - [ ] `package = lib.mkDefault pkgs.firefox`
  - [ ] `windowClass = lib.mkDefault "firefox"`
  - [ ] `desktopEntry = lib.mkDefault "firefox.desktop"`
  - [ ] `appId = lib.mkDefault "firefox"`
  - [ ] `windowClassAliases = lib.mkDefault [ "Navigator" ]`
- [ ] Add `editor` defaults:
  - [ ] `package = lib.mkDefault pkgs.geany`
  - [ ] `windowClass = lib.mkDefault "Geany"` (capitalized)
  - [ ] `desktopEntry = lib.mkDefault "geany.desktop"`
- [ ] Add `fileManager` defaults:
  - [ ] `package = lib.mkDefault pkgs.xfce.thunar`
  - [ ] `windowClass = lib.mkDefault "Thunar"` (capitalized)
  - [ ] `desktopEntry = lib.mkDefault "thunar.desktop"`
- [ ] Add `terminal` defaults:
  - [ ] `package = lib.mkDefault pkgs.kitty`
  - [ ] `windowClass = lib.mkDefault "kitty"`
  - [ ] `desktopEntry = lib.mkDefault "kitty.desktop"`
  - [ ] `appId = lib.mkDefault "kitty"`

### 1.5 Base Aggregator Export

- [ ] Contribute module to base aggregator: `flake.nixosModules.base = userDefaultsModule;`
  - This follows the established pattern (13+ modules contribute to `base`)
  - Host config already imports `config.flake.nixosModules.base`
  - Flake-parts merges all contributions automatically

**Verification:**
```bash
# Verify options are declared
nix eval '.#nixosConfigurations.system76.options.userDefaults.apps.type.description' 2>/dev/null && echo "Options declared"

# Verify default values
nix eval '.#nixosConfigurations.system76.config.userDefaults.apps.browser.windowClass'
# Expected: "firefox"

nix eval '.#nixosConfigurations.system76.config.userDefaults.apps.browser.package.name'
# Expected: "firefox-<version>"
```

---

## Phase 2: Helper Functions Library

### 2.1 Create Helper File

Create `lib/user-defaults-helpers.nix`:

- [ ] Add file header with usage documentation
- [ ] Define function signature: `{ lib, config }:`
- [ ] Bind `cfg = config.userDefaults;`

### 2.2 Implement Helper Functions

- [ ] Implement `getAppId`:
  ```nix
  getAppId = role:
    let app = cfg.apps.${role};
    in if app.appId != null then app.appId else app.windowClass;
  ```
- [ ] Implement `getAllWindowClasses`:
  ```nix
  getAllWindowClasses = role:
    let app = cfg.apps.${role};
    in [ app.windowClass ] ++ app.windowClassAliases;
  ```
- [ ] Implement `mkAssign` (with `lib.strings.escapeRegex`):
  ```nix
  mkAssign = role:
    let
      allClasses = getAllWindowClasses role;
      escapedClasses = map lib.strings.escapeRegex allClasses;
    in
    { class = "(?i)(?:${lib.concatStringsSep "|" escapedClasses})"; };
  ```

### 2.3 Export Helpers

- [ ] Export via `inherit` block:
  ```nix
  {
    inherit getAppId getAllWindowClasses mkAssign;
  }
  ```

**Verification:**
```bash
nix-instantiate --parse lib/user-defaults-helpers.nix
```

---

## Phase 3: Wiring & Propagation

### 3.1 NixOS Config Access

- [ ] Verify `config.userDefaults` is accessible in NixOS modules
  ```bash
  nix eval '.#nixosConfigurations.system76.config.userDefaults.enable'
  # Expected: true
  ```

### 3.2 Home Manager osConfig Access

- [ ] Confirm osConfig is available (no pre-verification command exists)
  - `osConfig` is auto-provided when HM is used as NixOS module
  - If missing, evaluation will fail with:
    ```
    error: function 'anonymous lambda' called without required argument 'osConfig'
    ```
  - This error IS the indicator—proceed to fix if seen
- [ ] If osConfig missing, add to `extraSpecialArgs` in `modules/home-manager/nixos.nix` (should not be needed)

---

## Phase 4: Validation Logic

### 4.1 Package Name Helper

In `modules/meta/user-defaults.nix`, add to `let` block:

- [ ] Implement `getPkgName`:
  ```nix
  getPkgName = pkg:
    pkg.pname or (builtins.parseDrvName (lib.getName pkg)).name;
  ```

### 4.2 Alignment Check Helper

- [ ] Implement `checkModuleAlignment`:
  - [ ] Extract `pkgName` using `moduleName` override or `getPkgName`
  - [ ] Build `modulePath = [ "programs" pkgName "extended" ]`
  - [ ] Check module existence with `lib.hasAttrByPath`
  - [ ] Only access module config if module exists
  - [ ] Check `moduleEnabled` and `modulePkg`
  - [ ] Return record with `role`, `pkgName`, `hasMismatch`, `hasModule`, `moduleEnabled`, `modulePkg`
- [ ] Define `alignmentChecks = lib.mapAttrsToList checkModuleAlignment cfg.apps;`

### 4.3 Assertions (strictValidation = true)

- [ ] Add `assertions` block wrapped in `lib.optionals cfg.strictValidation`
- [ ] Map over ALL `alignmentChecks` (not filtered)
- [ ] Set `assertion = !check.hasMismatch` (true = pass, false = fail)
- [ ] Include detailed error message with:
  - [ ] Role and package names
  - [ ] Resolution guidance
  - [ ] Reference to documentation

### 4.4 Warnings

- [ ] Add `warnings` block with:
  - [ ] `mismatchWarnings` (when `!cfg.strictValidation` and `hasMismatch`)
  - [ ] `noModuleWarnings` (when `!hasModule`)
  - [ ] `installWarnings` (when module exists but not enabled, not in systemPackages)
  - [ ] `coherenceWarnings` (when windowClass doesn't match package name)
- [ ] Concatenate all warning lists

### 4.5 Validation Toggle Test

- [ ] Verify `strictValidation` option exists and defaults to false:
  ```bash
  nix eval '.#nixosConfigurations.system76.config.userDefaults.strictValidation'
  # Expected: false
  ```
- [ ] Test `strictValidation = true` behavior (manual):
  - [ ] Temporarily add `userDefaults.strictValidation = true;` to config
  - [ ] Build with intentional package mismatch
  - [ ] **Verify:** Build fails with assertion error containing role name and fix guidance
  - [ ] Revert temporary change

---

## Phase 5: Consumer Migration

### 5.1 Refactor i3-config.nix

#### 5.1.1 Add osConfig Parameter

- [ ] Add `osConfig` to function signature:
  ```nix
  { config, pkgs, lib, osConfig, ... }:
  ```

#### 5.1.2 Create userDefaults Binding

- [ ] Add binding in `let` block:
  ```nix
  userDefaults = osConfig.userDefaults;
  ```

#### 5.1.3 Import Helper Functions

- [ ] Import helpers with correct config reference:
  ```nix
  helpers = import ../../lib/user-defaults-helpers.nix { inherit lib; config = osConfig; };
  inherit (helpers) mkAssign;
  ```

#### 5.1.4 Refactor commandsDefault

Split into two parts:

- [ ] Create `appsFromDefaults`:
  ```nix
  appsFromDefaults = {
    terminal = lib.getExe userDefaults.apps.terminal.package;
    browser = lib.getExe userDefaults.apps.browser.package;
  };
  ```
- [ ] Keep `wmSpecificCommands` with existing hardcoded values:
  - launcher, emoji, playerctl, volume, brightness, screenshot, logseqToggle, powerProfile
- [ ] Merge: `commandsDefault = appsFromDefaults // wmSpecificCommands;`

#### 5.1.5 Refactor Workspace Assigns

- [ ] Replace hardcoded class patterns with `mkAssign`:
  ```nix
  assigns = lib.mkOptionDefault {
    "1" = [ (mkAssign "editor") ];
    "2" = [ (mkAssign "browser") ];
    "3" = [ (mkAssign "fileManager") ];
  };
  ```

**Verification:**
```bash
# Test workspace assigns generation
nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.xsession.windowManager.i3.config.assigns' --json

# Expected to contain:
# "1": [{"class": "(?i)(?:Geany)"}]
# "2": [{"class": "(?i)(?:firefox|Navigator)"}]
# "3": [{"class": "(?i)(?:Thunar)"}]
```

### 5.2 Preserve Override Mechanism

- [ ] Verify `options.gui.i3.commands` still works:
  ```nix
  options.gui.i3.commands = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = commandsDefault;
    description = "Command strings for i3 keybindings (can override defaults)";
  };
  ```
- [ ] Verify user can override individual commands without `mkForce`

**Verification:**
```bash
# Full build test
nix build .#nixosConfigurations.system76.config.system.build.toplevel
```

---

## Phase 6: Final Validation

### 6.1 Type Checking Verification

- [ ] Verify invalid values fail with clear errors:
  ```bash
  # If someone sets: userDefaults.apps.browser.package = "firefox";
  # Should error: "value is a string while a package was expected"
  ```

### 6.2 Full Build Test

- [ ] Run complete build:
  ```bash
  nix build .#nixosConfigurations.system76.config.system.build.toplevel
  ```
- [ ] Verify no assertion failures
- [ ] Review any warnings produced

### 6.3 Partial Override Test

- [ ] Test that overriding single field preserves others:
  ```bash
  # userDefaults.apps.browser.package = pkgs.brave;
  # Should preserve: windowClass = "firefox" (needs manual update)
  ```

### 6.4 Runtime Verification (Post-Deploy)

- [ ] Open Firefox → should appear on workspace 2
- [ ] Open Geany → should appear on workspace 1
- [ ] Open Thunar → should appear on workspace 3
- [ ] Test `gui.i3.commands` override mechanism still works

### 6.5 WM_CLASS Verification Reference

Reference for verifying correct WM_CLASS values when adding new app roles:

```bash
# Run the application, then in another terminal:
xprop WM_CLASS
# Click on the application window
# Output example: WM_CLASS(STRING) = "geany", "Geany"
# The second value (instance class) is what i3 matches against
```

**Known WM_CLASS values for default apps:**

| Application | WM_CLASS |
|-------------|----------|
| Firefox | `firefox` (lowercase) or `Navigator` |
| Geany | `Geany` (capitalized) |
| Thunar | `Thunar` (capitalized) |
| Kitty | `kitty` (lowercase) |

- [ ] Verify WM_CLASS values match defaults in module (spot check at least one app)

---

## Phase 7: Cleanup

### 7.1 Remove Legacy Patterns

- [ ] Verify no `_module.args.userDefaults` injection exists (should be none)
- [ ] Verify no `specialArgs` injection for userDefaults (should be none)
- [ ] Confirm dendritic pattern auto-imports the module

### 7.2 Documentation

- [ ] Update plan document status from "Draft" to "Implemented"
- [ ] Add usage examples to module header comments
- [ ] Verify inline documentation matches implementation

---

## Future Work (Out of Scope)

These items are documented for future phases but NOT part of this implementation:

### Environment Variables (Step 2.2)

- [ ] Create NixOS module for session variables
- [ ] Set BROWSER, EDITOR, TERMINAL from userDefaults

### XDG MIME Associations (Step 2.3)

- [ ] Create Home Manager module for MIME associations
- [ ] Map browser to http/https handlers
- [ ] Map fileManager to inode/directory
- [ ] Map editor to text/plain

### Per-Host Overrides

- [ ] Extend pattern for host-specific default overrides

---

## Rollback Plan

If issues arise during implementation:

1. [ ] Revert i3-config.nix to hardcoded `commandsDefault` and assigns
2. [ ] Delete `modules/meta/user-defaults.nix`
3. [ ] Delete `lib/user-defaults-helpers.nix`
4. [ ] No flake.nix changes to revert (none were made)

---

## Quick Reference: Key Files

| File | Purpose |
|------|---------|
| `modules/meta/user-defaults.nix` | NixOS options module (CREATE) |
| `lib/user-defaults-helpers.nix` | Helper functions for WM consumers (CREATE) |
| `modules/window-manager/i3-config.nix` | Primary consumer to refactor (MODIFY) |
| `docs/drafts/user-defaults-implementation-plan.md` | Canonical specification |

---

## Progress Tracking

| Phase | Status | Completion |
|-------|--------|------------|
| Phase 0: Preparation | Not Started | 0% |
| Phase 1: Module Infrastructure | Not Started | 0% |
| Phase 2: Helper Functions | Not Started | 0% |
| Phase 3: Wiring & Propagation | Not Started | 0% |
| Phase 4: Validation Logic | Not Started | 0% |
| Phase 5: Consumer Migration | Not Started | 0% |
| Phase 6: Final Validation | Not Started | 0% |
| Phase 7: Cleanup | Not Started | 0% |
