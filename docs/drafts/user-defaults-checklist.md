# User Defaults Implementation Checklist

> **Status:** Ready for Implementation
> **Plan Document:** [user-defaults-implementation-plan.md](./user-defaults-implementation-plan.md)
> **Branch:** `feat/user-defaults`
> **Worktree:** `~/trees/nixos/feat-user-defaults`

## Instructions

- Complete tasks in order; dependencies are noted where critical
- Check off items as completed: `- [x]`
- Run verification commands after each phase
- Do not proceed to Phase 2 until Phase 1 verification passes

---

## Pre-Implementation Checklist

### Environment Verification

- [ ] Working in correct worktree: `cd ~/trees/nixos/feat-user-defaults`
- [ ] Branch is `feat/user-defaults`: `git branch --show-current`
- [ ] Working tree is clean: `git status`
- [ ] Dev shell is active: `nix develop`

### Dependency Verification

- [ ] Verify metaOwner pattern exists and works:
  ```bash
  nix eval --file lib/meta-owner-profile.nix
  ```
- [ ] Verify current i3-config.nix location:
  ```bash
  ls modules/window-manager/i3-config.nix
  ```
- [ ] Verify injection points exist:
  ```bash
  grep -l "_module.args" flake.nix modules/configurations/nixos.nix modules/system76/imports.nix modules/home-manager/nixos.nix
  ```

### WM_CLASS Verification

- [ ] Verify Firefox WM_CLASS: `xprop WM_CLASS` → click Firefox window
  - Expected: `"firefox", "firefox"` or `"Navigator", "firefox"`
  - Record actual value: _______________
- [ ] Verify Geany WM_CLASS: `xprop WM_CLASS` → click Geany window
  - Expected: `"geany", "Geany"`
  - Record actual value: _______________
- [ ] Verify Thunar WM_CLASS: `xprop WM_CLASS` → click Thunar window
  - Expected: `"thunar", "Thunar"`
  - Record actual value: _______________
- [ ] Verify Kitty WM_CLASS: `xprop WM_CLASS` → click Kitty window
  - Expected: `"kitty", "kitty"`
  - Record actual value: _______________

---

## Phase 1: Core Infrastructure

### Step 1.1: Create Data File

**File:** `lib/user-defaults.nix`

> **Note:** `lib/` directory already exists (contains `meta-owner-profile.nix`)

- [ ] Create `lib/user-defaults.nix` with content from plan Step 1.1
- [ ] Include workflow documentation header comment
- [ ] Define `apps.browser` with all fields (package, windowClass, appId, desktopEntry, windowClassAliases)
- [ ] Define `apps.editor` with required fields
- [ ] Define `apps.fileManager` with required fields
- [ ] Define `apps.terminal` with required fields
- [ ] **Verify:** Data file parses correctly:
  ```bash
  nix eval --file lib/user-defaults.nix
  ```
- [ ] **Verify:** Individual fields accessible:
  ```bash
  nix eval --file lib/user-defaults.nix apps.browser.package
  # Expected: "firefox"
  ```

### Step 1.2: Wire Up in flake.nix

**File:** `flake.nix`

- [ ] Locate the `let` block (around line 200)
- [ ] Add `userDefaults = import ./lib/user-defaults.nix;` after `ownerProfile`
- [ ] Locate `_module.args` block
- [ ] Add `userDefaults = userDefaults;` (or shorthand `inherit userDefaults;`)
- [ ] **Verify:** Flake still evaluates:
  ```bash
  nix flake show --accept-flake-config 2>&1 | head -20
  ```

### Step 1.3: Inject into NixOS Modules (Generic Handler)

**File:** `modules/configurations/nixos.nix`

- [ ] Add `userDefaults` to module function parameters
- [ ] Add `_module.args.userDefaults = userDefaults;` in the modules list
- [ ] Add `userDefaults` to `specialArgs` if present
- [ ] **Verify:** File has no syntax errors:
  ```bash
  nix eval '.#nixosModules' --apply 'x: builtins.attrNames x' 2>&1 | head -5
  ```

### Step 1.4: Inject into Host Modules (system76)

**File:** `modules/system76/imports.nix`

- [ ] Add `userDefaults` to module function parameters
- [ ] Locate `flake.nixosConfigurations.system76` block
- [ ] Add `_module.args.userDefaults = userDefaults;` in the modules list
- [ ] Add `userDefaults` to `specialArgs`
- [ ] **Verify:** system76 configuration still builds:
  ```bash
  nix eval '.#nixosConfigurations.system76.config.system.build.toplevel' 2>&1 | tail -3
  ```

### Step 1.5: Inject into Home Manager Modules (CRITICAL)

**File:** `modules/home-manager/nixos.nix`

- [ ] Add `userDefaults` to module function parameters (line ~5)
- [ ] Locate `config.home-manager` block
- [ ] Add `userDefaults` to `extraSpecialArgs`:
  ```nix
  extraSpecialArgs = {
    hasGlobalPkgs = true;
    inherit inputs metaOwner userDefaults;
  };
  ```
- [ ] **Verify:** Home Manager configuration accessible:
  ```bash
  nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.home.username'
  # Expected: "vx"
  ```

#### Step 1.5.1: Intermediate Home Manager Verification (CRITICAL)

> **Do not proceed until these pass.** HM injection is the most failure-prone step.

- [ ] **Verify:** userDefaults is accessible in HM context:
  ```bash
  # This will fail with "userDefaults not found" if injection failed
  nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.xsession.enable' 2>&1
  ```
- [ ] **Verify:** Build still succeeds after HM injection:
  ```bash
  nix build .#nixosConfigurations.system76.config.system.build.toplevel
  ```
- [ ] **Verify:** No infinite recursion errors (common with specialArgs issues)

### Step 1.6: Add Validation Module

**File:** `modules/meta/user-defaults-validation.nix`

- [ ] Create file with content from plan Step 1.6
- [ ] Include `validatePackagePath` function
- [ ] Include `checkModuleAlignment` function
- [ ] Enable `warnings = alignmentWarnings;` (not commented out)
- [ ] Export assertions and warnings
- [ ] **Verify:** Module parses correctly:
  ```bash
  nix-instantiate --parse modules/meta/user-defaults-validation.nix
  ```
- [ ] **Verify:** Validation module assertions run (no warnings for default config):
  ```bash
  nix build .#nixosConfigurations.system76.config.system.build.toplevel 2>&1 | grep -i "userDefaults" || echo "No warnings (good)"
  ```
- [ ] **Negative test:** Verify assertion catches invalid package path:
  ```bash
  # Temporarily break the data file to test assertion
  sed -i 's/package = "firefox"/package = "nonexistent-pkg"/' lib/user-defaults.nix
  nix build .#nixosConfigurations.system76.config.system.build.toplevel 2>&1 | grep -q "non-existent package path" && echo "Assertion works!"
  # Restore the file
  git checkout lib/user-defaults.nix
  ```

### Phase 1 Verification Gate

**Do not proceed to Phase 2 until ALL checks pass:**

- [ ] **Full build succeeds:**
  ```bash
  nix build .#nixosConfigurations.system76.config.system.build.toplevel
  ```
- [ ] **No assertion failures** (build would fail if any)
- [ ] **userDefaults accessible in Home Manager:**
  ```bash
  nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.xsession.windowManager.i3.config.terminal' 2>&1
  ```
- [ ] **Commit Phase 1 changes:**
  ```bash
  git add -A && git commit -m "feat(user-defaults): add core infrastructure (Phase 1)"
  ```

---

## Phase 2: Consumer Migration

### Step 2.1: Refactor i3-config.nix

**File:** `modules/window-manager/i3-config.nix`

#### 2.1.1: Add userDefaults Parameter

- [ ] Add `userDefaults` to module function parameters:
  ```nix
  { config, lib, pkgs, userDefaults, ... }:
  ```
- [ ] **Verify:** Module still loads (may have undefined references temporarily)

#### 2.1.2: Add Helper Functions

- [ ] Add `getPackage` helper function
- [ ] Add `getRoleExe` helper function
- [ ] Add `getWindowClass` helper function
- [ ] Add `getAppId` helper function
- [ ] Add `getAllWindowClasses` helper function
- [ ] Add `mkAssign` helper function (uses `lib.strings.escapeRegex` for safety)

> **Note:** Use `lib.strings.escapeRegex` from nixpkgs for regex escaping—do not implement a custom version. This is the idiomatic approach.

- [ ] **Verify:** Helpers are syntactically correct (full build test later)

#### 2.1.3: Refactor commandsDefault

- [ ] Create `appsFromDefaults` attrset:
  ```nix
  appsFromDefaults = {
    terminal = getRoleExe "terminal";
    browser = getRoleExe "browser";
  };
  ```
- [ ] Create `wmSpecificCommands` attrset (unchanged from current)
- [ ] Combine: `commandsDefault = appsFromDefaults // wmSpecificCommands;`
- [ ] **Verify:** commandsDefault structure unchanged for consumers

#### 2.1.4: Refactor Workspace Assigns

- [ ] Locate `assigns = lib.mkOptionDefault { ... };`
- [ ] Replace hardcoded patterns with `mkAssign` helper:
  ```nix
  assigns = lib.mkOptionDefault {
    "1" = [ (mkAssign "editor") ];
    "2" = [ (mkAssign "browser") ];
    "3" = [ (mkAssign "fileManager") ];
  };
  ```
- [ ] **Verify:** Assigns structure correct:
  ```bash
  nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.xsession.windowManager.i3.config.assigns' --json | jq .
  ```

#### 2.1.5: Verify No Regressions

- [ ] `gui.i3.commands` option still exists and has correct default
- [ ] `gui.i3.commands` can still be overridden
- [ ] Terminal keybinding uses correct package
- [ ] Browser keybinding uses correct package

### Step 2.1 Verification

- [ ] **Full build succeeds:**
  ```bash
  nix build .#nixosConfigurations.system76.config.system.build.toplevel
  ```
- [ ] **Workspace assigns generated correctly:**
  ```bash
  nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.xsession.windowManager.i3.config.assigns."2"' --json
  # Expected: [{"class":"(?i)(?:firefox|Navigator)"}]
  ```
- [ ] **Verify windowClassAliases included in regex:**
  ```bash
  # Browser assign should include both "firefox" and "Navigator" (from aliases)
  nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.xsession.windowManager.i3.config.assigns."2"' --json | grep -q "Navigator" && echo "Aliases included!"
  ```
- [ ] **Verify regex escaping works** (if any class has special chars):
  ```bash
  # The regex should have escaped special characters
  # For standard classes like "firefox", this just confirms no breakage
  nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.xsession.windowManager.i3.config.assigns."1"' --json | jq -r '.[0].class'
  # Should output a valid regex pattern like: (?i)(?:Geany)
  ```
- [ ] **Terminal command correct:**
  ```bash
  nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.xsession.windowManager.i3.config.terminal'
  # Expected: path containing "kitty"
  ```
- [ ] **Commit Step 2.1:**
  ```bash
  git add -A && git commit -m "feat(user-defaults): migrate i3-config.nix to role-based assigns"
  ```

### Step 2.2: Environment Variables (Future - Optional)

> **Note:** This step is marked as future in the plan. Complete only if desired.

- [ ] Create environment variables module or add to existing
- [ ] Set `BROWSER` from userDefaults
- [ ] Set `EDITOR` from userDefaults
- [ ] Set `TERMINAL` from userDefaults
- [ ] Verify variables are set in user session

### Step 2.3: XDG MIME Associations (Future - Optional)

> **Note:** This step is marked as future in the plan. Complete only if desired.

- [ ] Create or update XDG MIME module
- [ ] Set `x-scheme-handler/http` and `https` to browser
- [ ] Set `inode/directory` to fileManager
- [ ] Set `text/plain` to editor
- [ ] Verify MIME associations work

---

## Post-Implementation Validation

### Build Validation

- [ ] **Clean build from scratch:**
  ```bash
  nix build .#nixosConfigurations.system76.config.system.build.toplevel --rebuild
  ```
- [ ] **Flake check passes:**
  ```bash
  nix flake check --accept-flake-config
  ```
- [ ] **No warnings from validation module** (or only expected ones)

### Functional Validation

- [ ] **Deploy to test:**
  ```bash
  sudo nixos-rebuild test --flake .#system76
  ```
- [ ] **Open Firefox:** Appears on workspace 2
- [ ] **Open Geany:** Appears on workspace 1
- [ ] **Open Thunar:** Appears on workspace 3
- [ ] **Press $mod+Return:** Kitty terminal opens
- [ ] **Press $mod+b (or browser keybind):** Firefox opens

### Regression Testing

- [ ] **Override test:** Temporarily set custom `gui.i3.commands.browser`, rebuild, verify override works
- [ ] **Existing keybindings:** All other keybindings still work
- [ ] **i3status-rust:** Bar still displays correctly
- [ ] **Lock screen:** `$mod+l` still locks screen

### Documentation Validation

- [ ] **Data file has workflow comments:** Check `lib/user-defaults.nix` header
- [ ] **WM_CLASS values are correct:** Verified via xprop earlier

---

## Final Checklist

- [ ] All Phase 1 steps complete
- [ ] All Phase 2.1 steps complete
- [ ] Post-implementation validation passes
- [ ] No uncommitted changes: `git status`
- [ ] All commits have descriptive messages
- [ ] Ready for PR:
  ```bash
  gh pr create --title "feat(user-defaults): implement role-based application defaults" --body "$(cat <<'EOF'
  ## Summary
  - Implements centralized user defaults system for application role mapping
  - Adds Wayland support (appId field) and multi-class matching (windowClassAliases)
  - Includes validation module with package path assertions and alignment warnings
  - Migrates i3-config.nix to use role-based workspace assigns

  ## Test plan
  - [ ] Firefox opens on workspace 2
  - [ ] Geany opens on workspace 1
  - [ ] Thunar opens on workspace 3
  - [ ] Terminal keybinding opens Kitty
  - [ ] Override mechanism still works
  EOF
  )"
  ```

---

## Rollback Checklist

> **Use only if implementation fails and cannot be fixed forward.**

- [ ] Identify the last known-good commit: `git log --oneline`
- [ ] Reset to that commit: `git reset --hard <commit>`
- [ ] Verify build works: `nix build .#nixosConfigurations.system76.config.system.build.toplevel`
- [ ] Document what went wrong in the plan document

---

## Notes

_Use this section to record observations, issues, or deviations from the plan during implementation._

```
Date:
Issue:
Resolution:
```
