# User Defaults Implementation Plan

> **Status:** Draft
> **Scope:** System-wide default application configuration with WM-agnostic design

## Problem Statement

Application defaults are currently hardcoded in individual modules (e.g., i3-config.nix has `firefox`, `geany`, `thunar` literals). This creates:

1. **Duplication** - Same app referenced in multiple places (workspace assigns, keybindings, MIME types)
2. **Tight coupling** - Changing default browser requires editing multiple files
3. **WM lock-in** - Workspace assignments are i3-specific rather than role-based

### Existing Partial Solution

The current `i3-config.nix:241-252` already has a form of centralized defaults:

```nix
commandsDefault = {
  terminal = lib.getExe pkgs.kitty;
  browser = lib.getExe pkgs.firefox;
  # ...
};
```

This plan supersedes that pattern by making `userDefaults` the single source of truth, with `commandsDefault` derived from it.

## Design Goals

| Goal                      | Description                                                 |
| ------------------------- | ----------------------------------------------------------- |
| Single source of truth    | Define "browser = firefox" once, reference everywhere       |
| Role-based abstraction    | Modules reference "browser" role, not "firefox" package     |
| WM-agnostic               | Same defaults work for i3, sway, hyprland, or any future WM |
| Separation of concerns    | App choices separate from workspace layout                  |
| Follows existing patterns | Mirror metaOwner injection pattern exactly                  |
| Pure data file            | No dependencies on `pkgs` or `lib` in the data file         |

## Non-Goals (Explicit Scope Boundaries)

The following are explicitly **out of scope** for this implementation:

| Non-Goal             | Rationale                                                                                                  |
| -------------------- | ---------------------------------------------------------------------------------------------------------- |
| WM-specific commands | Launcher, emoji picker, screenshot commands stay hardcoded in WM configs (they have WM-specific arguments) |
| System utilities     | Media controls (`playerctl`), volume (`pamixer`), brightness (`xbacklight`) are not "user default apps"    |
| Custom scripts       | `toggleLogseqScript`, `powerProfileScript` remain in i3-config.nix (app-specific, not role-based)          |
| Per-host overrides   | Future extension; this phase establishes the base pattern only                                             |
| MIME type handling   | Marked as "future" in Phase 2; not part of initial implementation                                          |
| Package installation | `userDefaults` defines roles, not which packages to install (that's handled by existing module options)    |

### What Belongs in userDefaults vs WM Config

```
┌─────────────────────────────────────────────────────────────────────────┐
│ userDefaults.apps (this plan)                                           │
│ User-facing applications with abstract roles:                           │
│ • browser, editor, terminal, fileManager                                │
│ • Future: email, music, video, pdf                                      │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ WM-specific commands (stay in i3-config.nix)                            │
│ Commands with WM-specific arguments or complex pipelines:               │
│ • launcher: "${lib.getExe pkgs.rofi} -modi drun -show drun"             │
│ • emoji: "${lib.getExe pkgs.rofimoji} --selector rofi"                  │
│ • screenshot: "${lib.getExe pkgs.maim} -s -u | ${pkgs.xclip}..."        │
│ • Custom scripts: logseqToggle, powerProfile                            │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ System utilities (stay hardcoded)                                       │
│ Hardware/system controls, not user app preferences:                     │
│ • playerctl, pamixer, xbacklight                                        │
└─────────────────────────────────────────────────────────────────────────┘
```

## Success Criteria

Implementation is complete when:

| Criterion                   | Verification                                                            |
| --------------------------- | ----------------------------------------------------------------------- |
| Data file exists            | `nix eval --file lib/user-defaults.nix` succeeds                        |
| Injection works             | `userDefaults` parameter available in i3-config.nix                     |
| Validation assertions pass  | Build succeeds without assertion failures from validation module        |
| Workspace assigns use roles | `nix eval` shows `class` patterns derived from `userDefaults`           |
| Build succeeds              | `nix build .#nixosConfigurations.system76.config.system.build.toplevel` |
| Runtime correct             | Firefox→ws2, Geany→ws1, Thunar→ws3 after deployment                     |
| No regression               | Existing `gui.i3.commands` override mechanism still works               |

## Architecture

### Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│ lib/user-defaults.nix                                                   │
│ Pure data: { apps.browser.package = "firefox"; ... }                    │
│ (No pkgs/lib dependencies - imported before they exist)                 │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ import (in flake.nix let block)
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ flake.nix                                                               │
│ _module.args.userDefaults = import ./lib/user-defaults.nix;             │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ _module.args + specialArgs
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Injection Points (all must be updated)                                  │
│ - modules/configurations/nixos.nix (NixOS modules)                      │
│ - modules/system76/imports.nix (host-specific)                          │
│ - modules/home-manager/nixos.nix (Home Manager modules) ← CRITICAL      │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ userDefaults function parameter
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Consumer Modules (use injected userDefaults directly)                   │
│ - i3-config.nix: { lib, pkgs, userDefaults, ... }:                      │
│ - sway config (future)                                                  │
│ - xdg-mime module                                                       │
│ - environment variables                                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why Pure Data (No Package References in Data File)

The data file is imported in `flake.nix` **before** `pkgs` exists:

```nix
# flake.nix line 200
let
  ownerProfile = import ./lib/meta-owner-profile.nix;
  userDefaults = import ./lib/user-defaults.nix;  # pkgs doesn't exist here!
in
```

Therefore, `lib/user-defaults.nix` can only contain strings, numbers, and attribute sets—no package references. Package resolution happens at the point of consumption where `pkgs` is available.

### Data Structure

> **Canonical definition:** See [Step 1.1](#step-11-create-data-file) for the complete `lib/user-defaults.nix` file.

Each app role is a structured attribute set with required and optional fields:

**Required fields:**

| Field          | Type   | Purpose                                      | Example                       |
| -------------- | ------ | -------------------------------------------- | ----------------------------- |
| `package`      | String | `pkgs` attribute path for package resolution | `"firefox"`, `"xfce.thunar"`  |
| `windowClass`  | String | X11 WM_CLASS for window matching             | `"Geany"` (often capitalized) |
| `desktopEntry` | String | .desktop file name for MIME associations     | `"firefox.desktop"`           |

**Optional fields (for advanced use cases):**

| Field                | Type         | Purpose                                    | Example                             |
| -------------------- | ------------ | ------------------------------------------ | ----------------------------------- |
| `appId`              | String       | Wayland app_id (defaults to `windowClass`) | `"firefox"`, `"org.gnome.Nautilus"` |
| `windowClassAliases` | List[String] | Additional WM_CLASS values for matching    | `[ "Navigator" "firefox-default" ]` |

> **Note:** `appId` is needed for Wayland compositors (Hyprland, Sway) where app identifiers may differ from X11 WM_CLASS. For most apps they're identical, but Electron apps and some GTK apps differ. Helper functions fall back to `windowClass` if `appId` is not specified.

### Why Structured Data (Decoupling)

This explicit structure (vs. flat strings with fallbacks) is necessary because:

- WM_CLASS often differs from package name (capitalization, entirely different names)
- Desktop entry names don't always match package names
- Explicit is better than implicit fallbacks that silently fail

### Relationship to Module Package Options

`userDefaults` is intentionally **separate from and orthogonal to** the `programs.<name>.extended.package` module options. This separation is by design:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ userDefaults (this system)                                              │
│ • Purpose: Role→app mapping for WM integration                          │
│ • Contains: String package paths ("firefox", "xfce.thunar")             │
│ • Used by: Keybindings, workspace assigns, MIME associations            │
│ • Answers: "What app fulfills the browser role?"                        │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ programs.<name>.extended.package (existing module system)               │
│ • Purpose: Package variant selection for installation                   │
│ • Contains: Actual package derivation (pkgs.firefox-esr)                │
│ • Used by: environment.systemPackages                                   │
│ • Answers: "What variant of Firefox should be installed?"               │
└─────────────────────────────────────────────────────────────────────────┘
```

**Why no automatic integration:**

1. **Evaluation timing:** `userDefaults` is imported in `flake.nix` before `config` exists
2. **Different concerns:** "Firefox fills browser role" ≠ "install Firefox ESR"
3. **Multiple apps:** User may have Firefox (role) + Brave + Chrome all installed
4. **Explicitness:** Changing a module's package shouldn't silently change keybindings

**Coherence is enforced via assertions** (Step 1.6), not implicit integration.

See [Open Question #2 (Resolved)](#open-questions) for the full decision rationale.

## Implementation Steps

### Phase 1: Core Infrastructure

#### Step 1.1: Create data file

Create `lib/user-defaults.nix`:

```nix
# ════════════════════════════════════════════════════════════════════════════
# User Defaults - Application Role Mappings
# ════════════════════════════════════════════════════════════════════════════
#
# This file defines which applications fulfill abstract roles (browser, editor,
# terminal, etc.) for window manager integration.
#
# IMPORTANT: This is a pure data file. No pkgs or lib dependencies allowed
# (imported in flake.nix before they exist).
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ WORKFLOW: To change a default application (e.g., browser)              │
# ├─────────────────────────────────────────────────────────────────────────┤
# │ 1. Update `package` to the new package path (e.g., "brave")            │
# │ 2. Update `windowClass` to match the new app's WM_CLASS                │
# │    → Run `xprop WM_CLASS` and click the app window to find this        │
# │ 3. Update `desktopEntry` to the new app's .desktop filename            │
# │ 4. Optionally update `appId` if using Wayland (often same as class)    │
# │ 5. Ensure the app module is enabled (e.g., programs.brave.extended)    │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Field reference:
#   package           - pkgs attribute path (required)
#   windowClass       - X11 WM_CLASS for i3/bspwm matching (required)
#   desktopEntry      - .desktop file for MIME associations (required)
#   appId             - Wayland app_id, defaults to windowClass (optional)
#   windowClassAliases - Additional classes for multi-window apps (optional)
#
# ════════════════════════════════════════════════════════════════════════════
{
  apps = {
    browser = {
      package = "firefox";
      windowClass = "firefox";
      appId = "firefox";  # Same as windowClass for Firefox
      desktopEntry = "firefox.desktop";
      # Firefox can appear as multiple classes depending on profile/mode
      windowClassAliases = [ "Navigator" ];
    };

    editor = {
      package = "geany";
      windowClass = "Geany";  # Note: capitalized
      desktopEntry = "geany.desktop";
    };

    fileManager = {
      package = "xfce.thunar";
      windowClass = "Thunar";  # Note: capitalized
      desktopEntry = "thunar.desktop";
    };

    terminal = {
      package = "kitty";
      windowClass = "kitty";
      appId = "kitty";  # Same for Wayland
      desktopEntry = "kitty.desktop";
    };
  };
}
```

#### Step 1.2: Wire up in flake.nix

Update `flake.nix` (around line 200):

```nix
let
  ownerProfile = import ./lib/meta-owner-profile.nix;
  userDefaults = import ./lib/user-defaults.nix;
in
inputs.flake-parts.lib.mkFlake { inherit inputs; } {
  # ...
  _module.args = {
    rootPath = ./.;
    inherit inputs;
    pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    metaOwner = ownerProfile;
    userDefaults = userDefaults;  # Add this
  };
}
```

#### Step 1.3: Inject into NixOS modules (generic handler)

Update `modules/configurations/nixos.nix`.

> **Note:** This module handles generic `configurations.nixos.*` definitions. Step 1.4 handles system76 specifically, which creates its own `flake.nixosConfigurations.system76` directly. Both must be updated for consistency and to support future hosts using either pattern.

```nix
{ lib, config, inputs, metaOwner, userDefaults, ... }:
let
  nixosConfigs = lib.flip lib.mapAttrs config.configurations.nixos (
    _name:
    { module }:
    inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          _module.args.metaOwner = metaOwner;
          _module.args.userDefaults = userDefaults;  # Add this
        }
        module
      ];
      specialArgs = {
        inherit metaOwner userDefaults;  # Add userDefaults
      };
    }
  );
in
# ...
```

#### Step 1.4: Inject into host modules (system76-specific)

Update `modules/system76/imports.nix` in the `flake.nixosConfigurations.system76` block.

> **Note:** This is the actual injection point used for the system76 host. The module creates `flake.nixosConfigurations.system76` directly, bypassing the generic handler in Step 1.3.

```nix
{ config, lib, inputs, metaOwner, userDefaults, ... }:
# ...
flake.nixosConfigurations.system76 = inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    {
      _module.args.metaOwner = metaOwner;
      _module.args.userDefaults = userDefaults;  # Add this
      _module.args.inputs = inputs;
    }
    # ...
  ];
  specialArgs = {
    inherit inputs metaOwner userDefaults;  # Add userDefaults
  };
};
```

#### Step 1.5: Inject into Home Manager modules (CRITICAL)

Update `modules/home-manager/nixos.nix` in the `config.home-manager` block, specifically the `extraSpecialArgs` attribute:

```nix
config.home-manager = {
  useGlobalPkgs = true;
  extraSpecialArgs = {
    hasGlobalPkgs = true;
    inherit inputs metaOwner userDefaults;  # Add userDefaults
  };
  # ...
};
```

**This step is critical** - without it, Home Manager modules like `i3-config.nix` won't receive `userDefaults`.

#### Step 1.6: Add validation module

Create `modules/meta/user-defaults-validation.nix` to ensure coherence between userDefaults and installed packages:

```nix
# Validation assertions for userDefaults
# Ensures package paths exist and warns about module mismatches
{ config, lib, pkgs, userDefaults, ... }:
let
  # Validate that a package path exists in pkgs
  validatePackagePath = role: appDef:
    let
      pathParts = lib.splitString "." appDef.package;
      pkg = lib.attrByPath pathParts null pkgs;
    in
    {
      assertion = pkg != null;
      message = ''
        userDefaults.apps.${role}.package references non-existent package path: "${appDef.package}"

        This can happen when:
        - The package name is misspelled
        - The package was removed from nixpkgs
        - The package path structure changed

        Fix: Update lib/user-defaults.nix with the correct package path.
      '';
    };

  # Generate assertions for all app roles
  packagePathAssertions = lib.mapAttrsToList validatePackagePath userDefaults.apps;

  # Check if role package matches enabled module package
  # Enabled by default to catch potential misconfigurations
  checkModuleAlignment = role: appDef:
    let
      pathParts = lib.splitString "." appDef.package;
      pkgName = lib.last pathParts;
      moduleEnabled = config.programs.${pkgName}.extended.enable or false;
      modulePkg = config.programs.${pkgName}.extended.package or null;
      rolePackage = lib.attrByPath pathParts null pkgs;
    in
    lib.optional (moduleEnabled && modulePkg != null && modulePkg != rolePackage) ''
      userDefaults alignment notice: userDefaults.apps.${role} uses "${appDef.package}"
      but programs.${pkgName}.extended.package is set to a different derivation.

      This is valid if intentional (e.g., module installs firefox-esr but role uses firefox).
      See the "Relationship to Module Package Options" section in the implementation plan.

      To silence this warning, ensure package paths match or acknowledge the divergence.
    '';

  # Collect alignment warnings
  alignmentWarnings = lib.flatten (lib.mapAttrsToList checkModuleAlignment userDefaults.apps);
in
{
  assertions = packagePathAssertions;

  # Alignment warnings enabled by default to catch misconfigurations
  # These are informational and don't fail the build
  warnings = alignmentWarnings;
}
```

**What this validates:**

| Check                    | Type                         | Failure Mode                           |
| ------------------------ | ---------------------------- | -------------------------------------- |
| Package path exists      | Assertion (hard fail)        | Build fails with clear error message   |
| Module package alignment | Warning (enabled by default) | Build succeeds with informational note |

> **Note:** Alignment warnings are enabled by default per reviewer recommendation. They help catch "ghost package" scenarios where userDefaults references a package that's defined in nixpkgs but not actually installed via a module. This is informational only—the build will succeed, but the warning prompts the user to verify their configuration.

**Why this matters:**

Without validation, a typo in `lib/user-defaults.nix` (e.g., `"fireofx"` instead of `"firefox"`) would cause a confusing runtime error when i3-config.nix tries to resolve the package path.

### Phase 2: Consumer Migration

#### Step 2.1: Refactor i3-config.nix

The existing `commandsDefault` pattern should derive from `userDefaults`:

**Current** (hardcoded):

```nix
commandsDefault = {
  terminal = lib.getExe pkgs.kitty;
  browser = lib.getExe pkgs.firefox;
  # ...
};

assigns = lib.mkOptionDefault {
  "1" = [ { class = "(?i)(?:geany)"; } ];
  "2" = [ { class = "(?i)(?:firefox)"; } ];
  "3" = [ { class = "(?i)(?:thunar)"; } ];
};
```

**Refactored** (role-based):

```nix
{ config, lib, pkgs, userDefaults, ... }:
let
  # ══════════════════════════════════════════════════════════════════════
  # Helpers for userDefaults access
  # ══════════════════════════════════════════════════════════════════════

  # Resolve nested package path like "xfce.thunar"
  getPackage = role:
    lib.getAttrFromPath
      (lib.splitString "." userDefaults.apps.${role}.package)
      pkgs;

  # Get executable for a role
  getRoleExe = role: lib.getExe (getPackage role);

  # Get X11 window class for a role
  getWindowClass = role: userDefaults.apps.${role}.windowClass;

  # Get Wayland app_id for a role (falls back to windowClass)
  getAppId = role:
    userDefaults.apps.${role}.appId or userDefaults.apps.${role}.windowClass;

  # Get all window classes for a role (base + aliases)
  getAllWindowClasses = role:
    let
      base = userDefaults.apps.${role}.windowClass;
      aliases = userDefaults.apps.${role}.windowClassAliases or [];
    in
    [ base ] ++ aliases;

  # Generate WM assign pattern (supports aliases for multi-class apps)
  mkAssign = role:
    let
      allClasses = getAllWindowClasses role;
    in
    { class = "(?i)(?:${lib.concatStringsSep "|" allClasses})"; };

  # ══════════════════════════════════════════════════════════════════════
  # Commands: derived from userDefaults + WM-specific (see Non-Goals)
  # ══════════════════════════════════════════════════════════════════════

  # Commands derived from userDefaults (app roles)
  appsFromDefaults = {
    terminal = getRoleExe "terminal";
    browser = getRoleExe "browser";
  };

  # WM-specific commands (NOT from userDefaults - see Non-Goals section)
  wmSpecificCommands = {
    launcher = "${lib.getExe pkgs.rofi} -modi drun -show drun";
    emoji = "${lib.getExe pkgs.rofimoji} --selector rofi";
    playerctl = lib.getExe pkgs.playerctl;
    volume = lib.getExe pkgs.pamixer;
    brightness = lib.getExe pkgs.xorg.xbacklight;
    screenshot = "${lib.getExe pkgs.maim} -s -u | ${lib.getExe pkgs.xclip} -selection clipboard -t image/png -i";
    logseqToggle = lib.getExe toggleLogseqScript;
    powerProfile = lib.getExe powerProfileScript;
  };

  # Combined commandsDefault (maintains existing structure)
  commandsDefault = appsFromDefaults // wmSpecificCommands;
in
{
  # Existing options.gui.i3.commands pattern preserved for overrides
  options.gui.i3.commands = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = commandsDefault;
    description = "Command strings for i3 keybindings (can override defaults)";
  };

  config.xsession.windowManager.i3.config = {
    # Terminal from userDefaults, launcher stays WM-specific
    inherit (config.gui.i3.commands) terminal;
    menu = config.gui.i3.commands.launcher;

    # Workspace assigns use role-based helpers
    assigns = lib.mkOptionDefault {
      "1" = [ (mkAssign "editor") ];
      "2" = [ (mkAssign "browser") ];
      "3" = [ (mkAssign "fileManager") ];
    };
  };
}
```

**Key changes:**

- `userDefaults` received as function parameter (not `config.flake.lib.*`)
- Helpers defined locally where `pkgs` and `lib` are available
- **Separation clear**: `appsFromDefaults` vs `wmSpecificCommands`
- Existing `options.gui.i3.commands` pattern preserved for overrides
- Workspace-to-role mapping remains in i3-config.nix (WM-specific)

#### Step 2.2: Environment variables (future)

```nix
{ lib, pkgs, userDefaults, ... }:
let
  # Reuse the same helper pattern
  getPackage = role:
    lib.getAttrFromPath
      (lib.splitString "." userDefaults.apps.${role}.package)
      pkgs;
in
{
  environment.sessionVariables = {
    BROWSER = lib.getExe (getPackage "browser");
    EDITOR = lib.getExe (getPackage "editor");
    TERMINAL = lib.getExe (getPackage "terminal");
  };
}
```

#### Step 2.3: XDG MIME associations (future)

```nix
{ userDefaults, ... }:
let
  getDesktopEntry = role: userDefaults.apps.${role}.desktopEntry;
in
{
  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/http" = getDesktopEntry "browser";
    "x-scheme-handler/https" = getDesktopEntry "browser";
    "text/html" = getDesktopEntry "browser";
    "inode/directory" = getDesktopEntry "fileManager";
    "text/plain" = getDesktopEntry "editor";
  };
}
```

## File Changes Summary

| File                                        | Action | Description                                            |
| ------------------------------------------- | ------ | ------------------------------------------------------ |
| `lib/user-defaults.nix`                     | Create | Pure data file with structured app role mappings       |
| `flake.nix`                                 | Modify | Import and inject userDefaults via `_module.args`      |
| `modules/configurations/nixos.nix`          | Modify | Pass userDefaults to NixOS modules                     |
| `modules/system76/imports.nix`              | Modify | Pass userDefaults to host modules                      |
| `modules/home-manager/nixos.nix`            | Modify | Pass userDefaults via `extraSpecialArgs` (CRITICAL)    |
| `modules/meta/user-defaults-validation.nix` | Create | Assertions for package path validity and coherence     |
| `modules/window-manager/i3-config.nix`      | Modify | Derive `commandsDefault` and assigns from userDefaults |

## Testing Strategy

### 1. Data file validation

```bash
# Verify data file structure
nix eval --file lib/user-defaults.nix
nix eval --file lib/user-defaults.nix apps.browser.package
# Expected: "firefox"
```

### 2. Package resolution test

```bash
# Verify nested package path resolution works (e.g., "xfce.thunar")
nix eval --expr '
  let
    pkgs = import <nixpkgs> {};
    lib = pkgs.lib;
    path = lib.splitString "." "xfce.thunar";
  in lib.getAttrFromPath path pkgs
' --json | head -c 100
# Should show derivation info, not error
```

### 3. Home Manager integration (critical path)

```bash
# Test that workspace assigns are generated with correct window classes
nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.xsession.windowManager.i3.config.assigns' --json

# Expected output should contain:
# "1": [{"class": "(?i)(?:Geany)"}]
# "2": [{"class": "(?i)(?:firefox)"}]
# "3": [{"class": "(?i)(?:Thunar)"}]
```

### 4. Build verification

```bash
# Full build test
nix build .#nixosConfigurations.system76.config.system.build.toplevel

# i3 config is generated by Home Manager into the user's home directory
# After build, check via the activation script or nix eval:
nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.xsession.windowManager.i3.config.assigns."1"' --json
```

### 5. WM_CLASS verification (reference)

To verify correct WM_CLASS values for applications:

```bash
# Run the application, then in another terminal:
xprop WM_CLASS
# Click on the application window
# Output example: WM_CLASS(STRING) = "geany", "Geany"
# The second value (instance class) is what i3 matches against
```

Common WM_CLASS values for default apps:
| Application | WM_CLASS |
|-------------|----------|
| Firefox | `firefox` (lowercase) or `Navigator` |
| Geany | `Geany` (capitalized) |
| Thunar | `Thunar` (capitalized) |
| Kitty | `kitty` (lowercase) |

### 6. Runtime verification

After deployment:

- Open Firefox → should appear on workspace 2
- Open Geany → should appear on workspace 1
- Open Thunar → should appear on workspace 3
- Verify `gui.i3.commands` override still works (set custom value, rebuild, confirm)

## Rollback Plan

If issues arise:

1. Revert i3-config.nix to hardcoded `commandsDefault` and assigns
2. Keep lib/user-defaults.nix for future use
3. Remove injection from flake.nix, configurations/nixos.nix, system76/imports.nix, and home-manager/nixos.nix

## Dependencies

- Existing metaOwner pattern (reference implementation in `lib/meta-owner-profile.nix`)
- flake-parts `_module.args` mechanism
- Home Manager `extraSpecialArgs` mechanism
- No external dependencies

## Design Decisions

### Why no separate meta module?

The original plan included `modules/meta/user-defaults.nix` to expose `flake.lib.meta.defaults`. This was removed because:

1. **Context mismatch**: `config.flake.lib.*` is only accessible in flake-parts modules, not in NixOS/Home Manager modules where the data is consumed
2. **Unnecessary indirection**: The data can be injected directly via `_module.args`/`specialArgs`
3. **Follows metaOwner pattern**: `metaOwner` is injected directly without a wrapper module

### Why structured data instead of fallbacks?

The original plan used fallbacks:

```nix
getWindowClass = role: windowClasses.${role} or apps.${role};
```

This was changed to explicit structured data because:

1. **Silent failures**: Fallbacks hide misconfigurations
2. **Wrong assumptions**: Package name rarely equals WM_CLASS
3. **Explicit is better**: Each field serves a distinct purpose

### Why workspace mappings stay WM-specific?

Workspace-to-role mappings (e.g., "browser goes to workspace 2") remain in i3-config.nix because:

1. Workspace semantics differ between WMs
2. i3/sway have numbered workspaces; bspwm has named desktops
3. Some WMs don't have workspaces at all

## Open Questions

1. ~~Should `windowClass` be auto-derived from package metadata?~~ **Resolved: No.** WM_CLASS is set by the application at runtime, not stored in nixpkgs metadata. Manual specification is required.

2. ~~Should this integrate with `programs.<name>.extended.package` options?~~ **Resolved: No integration. Explicit separation by design.**

   **Decision:** `userDefaults` and `programs.<name>.extended.package` serve different purposes and remain orthogonal:

   | Aspect    | userDefaults                               | Module package option     |
   | --------- | ------------------------------------------ | ------------------------- |
   | Purpose   | Role→app mapping for WM integration        | Package variant selection |
   | Scope     | Keybindings, workspace assigns, MIME types | Package installation      |
   | Type      | String (resolved at consumption time)      | Actual package            |
   | Evaluated | Before config exists                       | During NixOS evaluation   |

   **Rationale:**
   - **Different concerns:** Choosing "Firefox fills the browser role" is separate from "install Firefox ESR variant"
   - **Evaluation timing:** userDefaults is parsed before `config` exists; cannot reference module options
   - **Multiple apps:** User may have Firefox (browser role) + Brave (also installed) + Chrome (also installed)
   - **Explicitness:** No magic "changing Firefox version changes my keybindings"

   **Use cases:**

   | Scenario                                 | userDefaults change               | Module option change                                   |
   | ---------------------------------------- | --------------------------------- | ------------------------------------------------------ |
   | Change browser from Firefox to Brave     | `browser.package = "brave"`       | Enable brave module                                    |
   | Use Firefox ESR as browser               | `browser.package = "firefox-esr"` | `programs.firefox.extended.package = pkgs.firefox-esr` |
   | Keep Firefox as default, also have Brave | No change                         | Enable both modules                                    |

   **Coherence guarantee:** Validation assertions (Step 1.6) verify that userDefaults references installed packages.

3. ~~How should applications with multiple window classes be handled?~~ **Resolved: Use `windowClassAliases` optional field.**

   Applications like Firefox can appear with different WM_CLASS values depending on profile, mode, or window type:
   - `firefox` (main window)
   - `Navigator` (legacy class)
   - `firefox-default` (profile-specific)

   **Solution:** The optional `windowClassAliases` field captures additional classes:

   ```nix
   browser = {
     package = "firefox";
     windowClass = "firefox";           # Primary class
     windowClassAliases = [ "Navigator" ];  # Additional classes to match
     desktopEntry = "firefox.desktop";
   };
   ```

   The `mkAssign` helper generates a regex that matches all classes:

   ```nix
   mkAssign = role:
     let
       allClasses = getAllWindowClasses role;  # [ "firefox" "Navigator" ]
     in
     { class = "(?i)(?:${lib.concatStringsSep "|" allClasses})"; };
   # Result: { class = "(?i)(?:firefox|Navigator)"; }
   ```

   **Finding WM_CLASS values:** Run `xprop WM_CLASS` and click each application window to discover all classes an app uses.
