# User Defaults Implementation Plan

> **Status:** Draft (Reviewed - fixes applied per nixos-manual verification)
> **Scope:** System-wide default application configuration with WM-agnostic design
> **Last Review:** Validated against `nixos-manual/development/` documentation

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

| Goal                       | Description                                                       |
| -------------------------- | ----------------------------------------------------------------- |
| Single source of truth     | Define "browser = firefox" once, reference everywhere             |
| Role-based abstraction     | Modules reference "browser" role, not "firefox" package           |
| WM-agnostic                | Same defaults work for i3, sway, hyprland, or any future WM       |
| Separation of concerns     | App choices separate from workspace layout                        |
| NixOS-native type safety   | Use `types.submodule` with proper option declarations             |
| Compile-time validation    | Type checking and assertions catch errors before runtime          |
| Auto-generated docs        | Option declarations produce manual entries automatically          |

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

| Criterion                   | Verification                                                                          |
| --------------------------- | ------------------------------------------------------------------------------------- |
| Options module exists       | `nix eval '.#nixosConfigurations.system76.config.userDefaults.apps.browser'` succeeds |
| Type checking works         | Invalid values (e.g., `package = 123`) fail with clear type error                     |
| Validation assertions pass  | Build succeeds without assertion failures from validation module                      |
| Workspace assigns use roles | `nix eval` shows `class` patterns derived from `config.userDefaults.apps`             |
| Build succeeds              | `nix build .#nixosConfigurations.system76.config.system.build.toplevel`               |
| Runtime correct             | Firefox→ws2, Geany→ws1, Thunar→ws3 after deployment                                   |
| No regression               | Existing `gui.i3.commands` override mechanism still works                             |

## Architecture

### Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│ modules/meta/user-defaults.nix                                          │
│ NixOS options module with types.submodule:                              │
│ • options.userDefaults.apps.<role>.package (types.package)              │
│ • options.userDefaults.apps.<role>.windowClass (types.str)              │
│ • Defaults set via config.userDefaults.apps with mkDefault              │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ Contributed to flake.nixosModules.base
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ NixOS Module Evaluation                                                 │
│ • pkgs is available → direct package references work                    │
│ • Type checking via types.package, types.str, etc.                      │
│ • Merge semantics for multi-module definitions                          │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ config.userDefaults.apps
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ lib/user-defaults-helpers.nix                                           │
│ Convenience functions for WM consumers:                                 │
│ • mkAssign: Generate window class regex patterns                        │
│ • getAllWindowClasses: Collect base + aliases                           │
│ (Package access via config.userDefaults.apps.*.package directly)        │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ Import helpers where needed
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Consumer Modules (use config.userDefaults.apps)                         │
│ - i3-config.nix: config.userDefaults.apps.browser.package               │
│ - sway config (future)                                                  │
│ - xdg-mime module                                                       │
│ - environment variables                                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why NixOS Options Module (Not Pure Data File)

The original design used a pure data file imported before `pkgs` exists. This approach was replaced with a proper NixOS options module for the following benefits:

**Type Safety:**

```nix
# With types.package, this fails at evaluation time with a clear error:
userDefaults.apps.browser.package = "not-a-package";

# Without types, this would fail at runtime when trying to use lib.getExe
```

**Direct Package References:**

```nix
# OLD: String path requiring runtime resolution
package = "firefox";  # Needs: lib.getAttrFromPath (lib.splitString "." ...) pkgs

# NEW: Direct package reference
package = pkgs.firefox;  # Works directly: lib.getExe cfg.apps.browser.package
```

**Auto-Generated Documentation:**

Options declared with `lib.mkOption` automatically appear in the NixOS manual with descriptions, types, defaults, and examples.

**Standard NixOS Patterns:**

Per `nixos-manual/development/settings-options.section.md`, structured configuration should use `types.submodule` with proper option declarations. This follows the same pattern as `services.*.settings` options throughout NixOS.

### Data Structure

> **Canonical definition:** See [Step 1.1](#step-11-create-options-module) for the complete `modules/meta/user-defaults.nix` file.

Each app role is a submodule with typed options:

**Required options:**

| Option         | Type            | Purpose                                  | Example                          |
| -------------- | --------------- | ---------------------------------------- | -------------------------------- |
| `package`      | `types.package` | Package derivation for this role         | `pkgs.firefox`, `pkgs.xfce.thunar` |
| `windowClass`  | `types.str`     | X11 WM_CLASS for window matching         | `"Geany"` (often capitalized)    |
| `desktopEntry` | `types.str`     | .desktop file name for MIME associations | `"firefox.desktop"`              |

**Optional options (with defaults):**

| Option               | Type                      | Default         | Purpose                                        |
| -------------------- | ------------------------- | --------------- | ---------------------------------------------- |
| `appId`              | `types.nullOr types.str`  | `null`          | Wayland app_id (falls back to class)           |
| `windowClassAliases` | `types.listOf types.str`  | `[]`            | Additional WM_CLASS values                     |
| `moduleName`         | `types.nullOr types.str`  | `null`          | Override programs.* namespace for validation   |

> **Note:** `appId` is needed for Wayland compositors (Hyprland, Sway) where app identifiers may differ from X11 WM_CLASS. For most apps they're identical, but Electron apps and some GTK apps differ. Helper functions fall back to `windowClass` if `appId` is `null`.

### Why Structured Data (Decoupling)

This explicit structure (vs. flat strings with fallbacks) is necessary because:

- WM_CLASS often differs from package name (capitalization, entirely different names)
- Desktop entry names don't always match package names
- Explicit is better than implicit fallbacks that silently fail

### Relationship to Module Package Options

`userDefaults.apps` is intentionally **separate from and orthogonal to** the `programs.<name>.extended.package` module options. This separation is by design:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ userDefaults.apps (this system)                                         │
│ • Purpose: Role→app mapping for WM integration                          │
│ • Contains: Package derivations (types.package)                         │
│ • Used by: Keybindings, workspace assigns, MIME associations            │
│ • Answers: "What app fulfills the browser role?"                        │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ programs.<name>.extended.package (existing module system)               │
│ • Purpose: Package variant selection for installation                   │
│ • Contains: Package derivation for that specific module                 │
│ • Used by: environment.systemPackages                                   │
│ • Answers: "What variant of Firefox should be installed?"               │
└─────────────────────────────────────────────────────────────────────────┘
```

**Why no automatic integration:**

1. **Different concerns:** "Firefox fills browser role" ≠ "install Firefox ESR"
2. **Multiple apps:** User may have Firefox (role) + Brave + Chrome all installed
3. **Explicitness:** Changing a module's package shouldn't silently change keybindings

**Coherence is enforced via assertions** (Step 1.5), not implicit integration.

See [Open Question #2 (Resolved)](#open-questions) for the full decision rationale.

## Implementation Steps

### Phase 1: Core Infrastructure

#### Step 1.1: Create options module

Create `modules/meta/user-defaults.nix`:

```nix
# ════════════════════════════════════════════════════════════════════════════
# User Defaults - Application Role Mappings (NixOS Options Module)
# ════════════════════════════════════════════════════════════════════════════
#
# This module defines which applications fulfill abstract roles (browser, editor,
# terminal, etc.) for window manager integration using proper NixOS options.
#
# Benefits over pure data file:
# • Type checking via types.package, types.str, etc.
# • Auto-generated documentation in NixOS manual
# • Proper merge semantics for multi-module definitions
# • Better error messages with source locations
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ ARCHITECTURE CONSTRAINT: osConfig Dependency                           │
# ├─────────────────────────────────────────────────────────────────────────┤
# │ Home Manager modules consuming userDefaults MUST access it via:        │
# │   let userDefaults = osConfig.userDefaults; in ...                     │
# │                                                                        │
# │ This requires Home Manager to be configured as a NixOS module (via     │
# │ home-manager.nixosModules.home-manager). The following are NOT         │
# │ supported:                                                             │
# │   • Standalone Home Manager deployments (non-NixOS Linux)              │
# │   • nix-darwin + Home Manager (macOS)                                  │
# │   • Any configuration where osConfig is unavailable                    │
# │                                                                        │
# │ This limitation is acceptable for this repository which manages a      │
# │ single NixOS host (system76) with user vx.                             │
# └─────────────────────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ WORKFLOW: To change a default application (e.g., browser)              │
# ├─────────────────────────────────────────────────────────────────────────┤
# │ 1. Update `package` to the new package (e.g., pkgs.brave)              │
# │ 2. Update `windowClass` to match the new app's WM_CLASS                │
# │    → Run `xprop WM_CLASS` and click the app window to find this        │
# │ 3. Update `desktopEntry` to the new app's .desktop filename            │
# │ 4. Optionally update `appId` if using Wayland (often same as class)    │
# │ 5. Ensure the app module is enabled (e.g., programs.brave.extended)    │
# │ 6. Optionally set `moduleName` if package pname ≠ module namespace     │
# └─────────────────────────────────────────────────────────────────────────┘
#
# ════════════════════════════════════════════════════════════════════════════

# NOTE: This module contributes to flake.nixosModules.base (the aggregator).
# Multiple files export to `base` and flake-parts merges them. The host config
# imports `config.flake.nixosModules.base` once, receiving all contributions.

{ config, lib, pkgs, ... }:
let
  # ══════════════════════════════════════════════════════════════════════════
  # NixOS Module Definition (contributed to flake.nixosModules.base aggregator)
  # ══════════════════════════════════════════════════════════════════════════
  userDefaultsModule = { config, lib, pkgs, ... }:
    let
      cfg = config.userDefaults;

      # App Role Submodule Definition
      appRoleModule = { name, ... }: {
        options = {
          package = lib.mkOption {
            type = lib.types.package;
            description = "The package for this application role.";
            example = lib.literalExpression "pkgs.firefox";
          };

          windowClass = lib.mkOption {
            type = lib.types.str;
            description = ''
              X11 WM_CLASS for window matching in i3/bspwm.
              Find this by running `xprop WM_CLASS` and clicking the app window.
              The second value (instance class) is typically what WMs match against.
            '';
            example = "Geany";
          };

          desktopEntry = lib.mkOption {
            type = lib.types.str;
            description = ".desktop file name for MIME type associations.";
            example = "firefox.desktop";
          };

          appId = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Wayland app_id for window matching in sway/hyprland.
              Falls back to windowClass if null. Only needed when app_id differs
              from WM_CLASS (common with Electron apps and some GTK apps).
            '';
            example = "org.gnome.Nautilus";
          };

          windowClassAliases = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = ''
              Additional WM_CLASS values for matching multi-window applications.
              Some apps (like Firefox) appear with different classes depending on
              profile, mode, or window type.
            '';
            example = [ "Navigator" "firefox-default" ];
          };

          moduleName = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Override the programs.* module namespace for validation.
              Use when the package's pname differs from the module path.

              For example, if using firefox-esr (pname = "firefox") but your
              module is at programs.firefox-esr.extended, set moduleName = "firefox-esr".

              When null (default), the module name is derived from the package's pname.
            '';
            example = "firefox-esr";
          };
        };
      };
    in
    {
      # ════════════════════════════════════════════════════════════════════════
      # Option Declarations
      # ════════════════════════════════════════════════════════════════════════
      options.userDefaults = {
        enable = lib.mkEnableOption "user defaults for application roles" // {
          default = true;
        };

        strictValidation = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to fail builds when userDefaults packages don't match
            programs.*.extended.package options. When false (default), mismatches
            produce warnings. When true, mismatches cause assertion failures.
          '';
        };

        apps = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule appRoleModule);
          default = {};
          description = ''
            Application role mappings. Each attribute defines an abstract role
            (browser, editor, terminal, etc.) with its associated package and
            window matching metadata.
          '';
          example = lib.literalExpression ''
            {
              browser = {
                package = pkgs.firefox;
                windowClass = "firefox";
                desktopEntry = "firefox.desktop";
              };
            }
          '';
        };
      };

      # ════════════════════════════════════════════════════════════════════════
      # Default Configuration
      # ════════════════════════════════════════════════════════════════════════
      # NOTE: mkDefault is applied to EACH FIELD individually, not to the whole
      # attrset. This allows users to override individual fields without having
      # to respecify all other fields.
      # ════════════════════════════════════════════════════════════════════════
      config = lib.mkIf cfg.enable {
        userDefaults.apps = {
          browser = {
            package = lib.mkDefault pkgs.firefox;
            windowClass = lib.mkDefault "firefox";
            desktopEntry = lib.mkDefault "firefox.desktop";
            appId = lib.mkDefault "firefox";
            # Firefox can appear as multiple classes depending on profile/mode
            windowClassAliases = lib.mkDefault [ "Navigator" ];
          };

          editor = {
            package = lib.mkDefault pkgs.geany;
            windowClass = lib.mkDefault "Geany";  # Note: capitalized
            desktopEntry = lib.mkDefault "geany.desktop";
          };

          fileManager = {
            package = lib.mkDefault pkgs.xfce.thunar;
            windowClass = lib.mkDefault "Thunar";  # Note: capitalized
            desktopEntry = lib.mkDefault "thunar.desktop";
          };

          terminal = {
            package = lib.mkDefault pkgs.kitty;
            windowClass = lib.mkDefault "kitty";
            desktopEntry = lib.mkDefault "kitty.desktop";
            appId = lib.mkDefault "kitty";
          };
        };
      };
    };
in
{
  # ══════════════════════════════════════════════════════════════════════════
  # Contribute to base aggregator (flake-parts merges multiple contributions)
  # ══════════════════════════════════════════════════════════════════════════
  flake.nixosModules.base = userDefaultsModule;
}
```

**Key differences from the original pure data approach:**

| Aspect              | Pure Data File               | NixOS Options Module                    |
| ------------------- | ---------------------------- | --------------------------------------- |
| Package references  | Strings (`"firefox"`)        | Actual packages (`pkgs.firefox`)        |
| Type checking       | None (runtime errors)        | Compile-time (`types.package`)          |
| Documentation       | Manual comments only         | Auto-generated in NixOS manual          |
| Error messages      | Generic Nix errors           | Option-specific with file locations     |
| Override mechanism  | N/A                          | `lib.mkForce`, `lib.mkDefault`, merging |
| Location            | `lib/user-defaults.nix`      | `modules/meta/user-defaults.nix`        |

**Verify:**
```bash
# Check module syntax
nix-instantiate --parse modules/meta/user-defaults.nix

# Verify options are available
nix eval '.#nixosConfigurations.system76.config.userDefaults.apps.browser.package' --json
```

#### Step 1.2: Create helper functions library

Create `lib/user-defaults-helpers.nix` to centralize helper functions for all consumers:

> **Why a separate file?** Helpers like `mkAssign` generate WM-specific patterns from config data. Extracting them avoids duplication when adding sway-config.nix, hyprland-config.nix, or other WM consumers.

> **Simplified from original:** Since `package` is now `types.package` (not a string path), the old `getPackage` helper that resolved string paths is no longer needed. Consumers access packages directly via `config.userDefaults.apps.browser.package`.

```nix
# lib/user-defaults-helpers.nix
# Helper functions for userDefaults consumers
# Usage: helpers = import ../../lib/user-defaults-helpers.nix { inherit lib config; };
{ lib, config }:
let
  cfg = config.userDefaults;

  # Get Wayland app_id for a role (falls back to windowClass if null)
  getAppId = role:
    let app = cfg.apps.${role};
    in if app.appId != null then app.appId else app.windowClass;

  # Get all window classes for a role (base + aliases)
  getAllWindowClasses = role:
    let app = cfg.apps.${role};
    in [ app.windowClass ] ++ app.windowClassAliases;

  # Generate WM assign pattern (supports aliases for multi-class apps)
  # Uses lib.strings.escapeRegex to handle special characters in class names
  mkAssign = role:
    let
      allClasses = getAllWindowClasses role;
      escapedClasses = map lib.strings.escapeRegex allClasses;
    in
    { class = "(?i)(?:${lib.concatStringsSep "|" escapedClasses})"; };
in
{
  inherit
    getAppId
    getAllWindowClasses
    mkAssign
    ;
}
```

**Key simplifications from original design:**

| Original Helper      | Status   | Reason                                           |
| -------------------- | -------- | ------------------------------------------------ |
| `getPackage`         | Removed  | Direct access: `cfg.apps.browser.package`        |
| `getRoleExe`         | Removed  | Direct access: `lib.getExe cfg.apps.browser.package` |
| `getWindowClass`     | Removed  | Direct access: `cfg.apps.browser.windowClass`    |
| `getAppId`           | Kept     | Null-fallback logic still useful                 |
| `getAllWindowClasses`| Kept     | Combines base class + aliases                    |
| `mkAssign`           | Kept     | Generates regex pattern for WM matching          |

**Verify:**
```bash
# Check syntax
nix-instantiate --parse lib/user-defaults-helpers.nix
```

#### Step 1.3: Module integration via base aggregator (no manual imports needed)

> **How it works:** The module contributes to `flake.nixosModules.base`, which is an aggregator that flake-parts **merges** from multiple file contributions. The host config (`modules/system76/imports.nix`) already imports `config.flake.nixosModules.base`, so this module's options become available automatically.

This follows the established pattern used by 13+ other modules (e.g., `modules/base/console.nix`, `modules/security/gnupg.nix`, `modules/boot/compression.nix`).

The module defines `options.userDefaults` which becomes available to all NixOS modules via the standard `config` parameter.

**No changes required to:**
- `flake.nix` - Dendritic pattern auto-discovers files; no manual import needed
- `modules/configurations/nixos.nix` - No `specialArgs` changes needed
- `modules/system76/imports.nix` - Already imports `config.flake.nixosModules.base`

#### Step 1.4: Home Manager access via osConfig

Home Manager modules access `userDefaults` through `osConfig`, which provides the NixOS configuration to Home Manager modules.

> **Important:** The `osConfig` special argument is automatically available when Home Manager is used as a NixOS module (the standard setup for this repository). It is NOT provided by `useGlobalPkgs` — that option only shares `pkgs`.

**osConfig availability:**

`osConfig` is automatically available when Home Manager is used as a NixOS module (via `home-manager.nixosModules.home-manager`). It is an evaluation-time special argument, NOT a config attribute—you cannot verify it with `nix eval` on the config output.

```bash
# Verify Home Manager is configured as a NixOS module (which provides osConfig)
nix eval '.#nixosConfigurations.system76.config.home-manager' --apply 'builtins.hasAttr "useGlobalPkgs"'
# If this returns `true`, Home Manager is properly configured and osConfig is available

# If osConfig is missing at runtime, you'll see a clear error like:
# "error: function 'anonymous lambda' called without required argument 'osConfig'"
```

If `osConfig` is somehow not available, add it explicitly to `extraSpecialArgs`:

```nix
# modules/home-manager/nixos.nix
config.home-manager = {
  useGlobalPkgs = true;
  extraSpecialArgs = {
    # osConfig is typically auto-provided when HM is a NixOS module,
    # but can be explicitly passed if needed:
    osConfig = config;
  };
};
```

**Home Manager module usage:**

```nix
# In a Home Manager module (e.g., i3-config.nix):
{ config, lib, pkgs, osConfig, ... }:
let
  # Access NixOS config via osConfig
  # osConfig is the NixOS configuration, config is the Home Manager configuration
  userDefaults = osConfig.userDefaults;
in
{
  # Use userDefaults.apps.browser.package, etc.
}
```

> **Why osConfig instead of specialArgs injection?** Per `nixos-manual/development/option-types.section.md`: "specialArgs should only be used for arguments that can't go through the module fixed-point." Since `userDefaults` is part of the NixOS config, accessing it via `osConfig` follows the standard pattern.

**Original design flaw (fixed):**

The original plan used BOTH `_module.args` AND `specialArgs` redundantly:
```nix
# OLD (redundant):
_module.args.userDefaults = userDefaults;
specialArgs = { inherit userDefaults; };
```

This is unnecessary. The new design:
1. Defines options in a standard NixOS module (exported via `flake.nixosModules`)
2. Options are available via `config.userDefaults` in NixOS modules
3. Home Manager accesses them via `osConfig.userDefaults`

#### Step 1.5: Add validation assertions

Add validation assertions to `modules/meta/user-defaults.nix` (extending the module from Step 1.1):

> **Pattern follows:** `nixos-manual/development/assertions.section.md` - assertions wrapped in `lib.mkIf` with clear error messages.

```nix
# Add to modules/meta/user-defaults.nix, extending the module from Step 1.1.
# This code goes INSIDE the userDefaultsModule definition, in the let block.

userDefaultsModule = { config, lib, pkgs, ... }:
  let
    cfg = config.userDefaults;

    # ════════════════════════════════════════════════════════════════════════
    # Helper: Extract package name reliably
    # ════════════════════════════════════════════════════════════════════════
    # Per nixos-manual/development/writing-modules.chapter.md: helper functions
    # belong in the `let` block, NOT in the `config` block.
    #
    # Uses pname if available, otherwise parses the derivation name to extract
    # just the package name without version (e.g., "firefox-138.0" -> "firefox")
    getPkgName = pkg:
      pkg.pname or (builtins.parseDrvName (lib.getName pkg)).name;

    # ════════════════════════════════════════════════════════════════════════
    # Validation helpers (used by assertions and warnings below)
    # ════════════════════════════════════════════════════════════════════════
    # Uses lib.hasAttrByPath for explicit module existence checking rather than
    # relying on `or` fallbacks which can silently skip validation.
    # ════════════════════════════════════════════════════════════════════════
    checkModuleAlignment = role: appDef:
      let
        # Allow override via moduleName option (for packages where pname ≠ module namespace)
        pkgName = appDef.moduleName or (getPkgName appDef.package);
        modulePath = [ "programs" pkgName "extended" ];

        # Explicitly check module existence - don't rely on `or` fallbacks
        hasModule = lib.hasAttrByPath modulePath config;

        # Only access module config if the module actually exists
        moduleConfig =
          if hasModule
          then lib.getAttrFromPath modulePath config
          else {};

        moduleEnabled = moduleConfig.enable or false;
        modulePkg = moduleConfig.package or null;

        # Only flag mismatch if module exists and is enabled with a different package
        hasMismatch = hasModule && moduleEnabled
          && modulePkg != null
          && modulePkg != appDef.package;
      in
      { inherit role pkgName hasMismatch hasModule moduleEnabled; app = appDef; inherit modulePkg; };

    alignmentChecks = lib.mapAttrsToList checkModuleAlignment cfg.apps;

  in
  {
    # ... options.userDefaults (from Step 1.1) ...

    config = lib.mkIf cfg.enable {
      # ... existing userDefaults.apps defaults ...

      # ══════════════════════════════════════════════════════════════════════
      # Validation: Assertions (only when strictValidation = true)
      # ══════════════════════════════════════════════════════════════════════
      # Per nixos-manual/development/assertions.section.md: assertions are a
      # list of { assertion; message; } records where the boolean `assertion`
      # determines pass (true) or fail (false).
      #
      # IMPORTANT: We process ALL checks, not just filtered failures. The
      # assertion boolean determines the outcome. Filtering would cause every
      # remaining assertion to fail, which is incorrect.
      #
      # NOTE: By default, package mismatches produce WARNINGS, not assertions.
      # Set userDefaults.strictValidation = true to make mismatches fail builds.
      # ══════════════════════════════════════════════════════════════════════

      assertions = lib.optionals cfg.strictValidation (
        map (check: {
          assertion = !check.hasMismatch;  # true = pass, false = fail
          message = ''
            userDefaults.apps.${check.role} package mismatch detected (strictValidation = true).

            Role package:   ${check.app.package.name or "unknown"}
            Module package: ${check.modulePkg.name or "unknown"}

            The userDefaults.apps.${check.role}.package differs from
            programs.${check.pkgName}.extended.package.

            This may be intentional (e.g., role uses firefox but module installs
            firefox-esr). To resolve:
            1. Align the packages to match, OR
            2. Set userDefaults.strictValidation = false (produces warning instead)

            See "Relationship to Module Package Options" in the implementation plan.
          '';
        }) alignmentChecks  # Process ALL checks - assertion boolean determines outcome
      );

      # ══════════════════════════════════════════════════════════════════════
      # Validation: Warnings (always enabled)
      # ══════════════════════════════════════════════════════════════════════
      # Per nixos-manual/development/assertions.section.md: warnings use
      # conditional list construction. Unlike assertions, warnings correctly
      # use filter+map since we're producing a string list, not boolean records.
      # ══════════════════════════════════════════════════════════════════════
      warnings =
        let
          # Warn about package mismatches (when strictValidation = false)
          mismatchWarnings = lib.optionals (!cfg.strictValidation) (
            map (check: ''
              userDefaults.apps.${check.role}: Package mismatch with programs.${check.pkgName}.extended.

              Role package:   ${check.app.package.name or "unknown"}
              Module package: ${check.modulePkg.name or "unknown"}

              This is valid if intentional. To silence: align packages or acknowledge divergence.
              To make this a build failure: set userDefaults.strictValidation = true.
            '') (lib.filter (c: c.hasMismatch) alignmentChecks)
          );

          # Warn when no matching programs.*.extended module exists
          # (validation was skipped - package may or may not be installed)
          noModuleWarnings = lib.concatMap (check:
            lib.optional (!check.hasModule) ''
              userDefaults.apps.${check.role}: No programs.${check.pkgName}.extended module found.

              Validation skipped for this role. Ensure the package is installed via:
              - A different module path (check moduleName option)
              - environment.systemPackages
              - Home Manager
              - nix profile
            ''
          ) alignmentChecks;

          # Warn if a role's package doesn't seem to be installed via any module
          installWarnings = lib.concatMap (check:
            let
              inSystemPackages = lib.elem check.app.package config.environment.systemPackages;
            in
            # Only warn if module exists but isn't enabled AND not in systemPackages
            lib.optional (check.hasModule && !check.moduleEnabled && !inSystemPackages) ''
              userDefaults.apps.${check.role}: Package "${check.pkgName}" may not be installed.

              programs.${check.pkgName}.extended.enable is false and the package is not
              in environment.systemPackages. The role will still work if the package
              is installed another way (e.g., via Home Manager or nix profile).
            ''
          ) alignmentChecks;

          # Warn if windowClass doesn't seem to match the package name
          # (helps catch configuration errors when changing default apps)
          coherenceWarnings = lib.concatMap (check:
            let
              pkgNameLower = lib.toLower (getPkgName check.app.package);
              classLower = lib.toLower check.app.windowClass;
              # Check if either contains the other (loose match)
              seemsCoherent = lib.hasInfix pkgNameLower classLower
                || lib.hasInfix classLower pkgNameLower
                || pkgNameLower == classLower;
            in
            lib.optional (!seemsCoherent) ''
              userDefaults.apps.${check.role}: windowClass "${check.app.windowClass}" may not match package "${pkgNameLower}".

              This could indicate a configuration error after changing the default app.
              Verify the correct WM_CLASS by running: xprop WM_CLASS
              Then click on the application window to see its actual class.
            ''
          ) alignmentChecks;
        in
        mismatchWarnings ++ noModuleWarnings ++ installWarnings ++ coherenceWarnings;
    };
  };
```

**What this validates:**

| Check                    | Type                                | Failure Mode                                       |
| ------------------------ | ----------------------------------- | -------------------------------------------------- |
| Module package alignment | Warning (default) or Assertion      | Warning by default; assertion if strictValidation  |
| No matching module       | Warning                             | Informs that validation was skipped                |
| Package installation     | Warning                             | Informational note if package may not be installed |
| windowClass coherence    | Warning                             | Suggests verifying WM_CLASS if name mismatch       |

**Key improvements from original design:**

| Issue                        | Original                          | Fixed                                                |
| ---------------------------- | --------------------------------- | ---------------------------------------------------- |
| Assertions not wrapped       | Flat `{ assertions = ...; }`      | Wrapped in `lib.mkIf cfg.enable`                     |
| Assertion filter bug         | Filter then assert (always fail)  | Process ALL checks; boolean determines outcome       |
| String path resolution       | `lib.attrByPath` on string        | Direct package comparison (`types.package`)          |
| Module existence check       | `or false` fallback (silent skip) | Explicit `lib.hasAttrByPath` with `hasModule` flag   |
| Ambiguous null check         | `pkg != null` (path vs value)     | Package derivation comparison                        |
| Error message source         | Generic                           | Includes package names and fix guidance              |
| Mismatch = hard failure      | Assertion always                  | Warning by default; `strictValidation` toggle        |
| Package name extraction      | `lib.getName` (includes version)  | `builtins.parseDrvName` (name only)                  |
| Module namespace mismatch    | pname assumed = module path       | `moduleName` option for explicit override            |
| windowClass coherence        | No validation                     | Warning if class doesn't match package name          |

> **Note:** With `types.package`, typos like `pkgs.fireofx` fail immediately at evaluation time with a clear "attribute 'fireofx' missing" error, rather than silently storing a bad string. This is a key benefit of the typed options approach.

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
# Home Manager module: modules/window-manager/i3-config.nix
{ config, lib, pkgs, osConfig, ... }:
let
  # ══════════════════════════════════════════════════════════════════════
  # Access userDefaults via osConfig (NixOS config passed to Home Manager)
  # ══════════════════════════════════════════════════════════════════════
  userDefaults = osConfig.userDefaults;

  # Import shared helpers for WM-specific pattern generation
  helpers = import ../../lib/user-defaults-helpers.nix { inherit lib; config = osConfig; };
  inherit (helpers) mkAssign;

  # ══════════════════════════════════════════════════════════════════════
  # Commands: derived from userDefaults + WM-specific (see Non-Goals)
  # ══════════════════════════════════════════════════════════════════════

  # Commands derived from userDefaults (app roles)
  # Direct package access - no helper needed thanks to types.package
  appsFromDefaults = {
    terminal = lib.getExe userDefaults.apps.terminal.package;
    browser = lib.getExe userDefaults.apps.browser.package;
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

    # ════════════════════════════════════════════════════════════════════
    # Workspace assigns use role-based helpers
    # ════════════════════════════════════════════════════════════════════
    # Priority documentation (per nixos-manual/development/option-def.section.md):
    #
    # lib.mkOptionDefault = lib.mkOverride 1500
    #
    # This gives these assigns the same priority as option defaults, meaning:
    # - User definitions in their config automatically take precedence (priority 100)
    # - Users don't need to use mkForce to override these values
    # - Other modules with normal definitions (priority 100) will override
    #
    # This is intentional: userDefaults provides sensible defaults that users
    # can easily customize without special override mechanisms.
    # ════════════════════════════════════════════════════════════════════
    assigns = lib.mkOptionDefault {
      "1" = [ (mkAssign "editor") ];
      "2" = [ (mkAssign "browser") ];
      "3" = [ (mkAssign "fileManager") ];
    };
  };
}
```

**Key changes from original design:**

| Aspect                  | Original                              | New                                         |
| ----------------------- | ------------------------------------- | ------------------------------------------- |
| Config access           | `userDefaults` function parameter     | `osConfig.userDefaults` (standard pattern)  |
| Package access          | `getRoleExe "browser"` helper         | `lib.getExe userDefaults.apps.browser.package` |
| Helpers needed          | `getPackage`, `getRoleExe`, etc.      | Only `mkAssign` (for regex generation)      |
| Type safety             | Runtime errors on bad paths           | Compile-time via `types.package`            |
| mkOptionDefault         | Undocumented                          | Documented with priority explanation        |

**Priority behavior documented:**

The `lib.mkOptionDefault` usage is now documented inline. Per `nixos-manual/development/option-def.section.md`:
- `mkOptionDefault` = `mkOverride 1500` (same as option defaults)
- User definitions have priority 100, so they automatically override
- No `mkForce` needed for user customization

#### Step 2.2: Environment variables (future)

```nix
# NixOS module for session variables
{ config, lib, ... }:
let
  userDefaults = config.userDefaults;
in
{
  # Direct package access - no helpers needed
  environment.sessionVariables = {
    BROWSER = lib.getExe userDefaults.apps.browser.package;
    EDITOR = lib.getExe userDefaults.apps.editor.package;
    TERMINAL = lib.getExe userDefaults.apps.terminal.package;
  };
}
```

#### Step 2.3: XDG MIME associations (future)

```nix
# Home Manager module for MIME associations
{ config, osConfig, ... }:
let
  userDefaults = osConfig.userDefaults;
in
{
  # Direct attribute access - no helpers needed
  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/http" = userDefaults.apps.browser.desktopEntry;
    "x-scheme-handler/https" = userDefaults.apps.browser.desktopEntry;
    "text/html" = userDefaults.apps.browser.desktopEntry;
    "inode/directory" = userDefaults.apps.fileManager.desktopEntry;
    "text/plain" = userDefaults.apps.editor.desktopEntry;
  };
}
```

## File Changes Summary

| File                                   | Action | Description                                                    |
| -------------------------------------- | ------ | -------------------------------------------------------------- |
| `modules/meta/user-defaults.nix`       | Create | NixOS options module with types.submodule for app roles        |
| `lib/user-defaults-helpers.nix`        | Create | Simplified helpers (mkAssign only, no package resolution)      |
| `modules/window-manager/i3-config.nix` | Modify | Use osConfig.userDefaults, direct package access               |
| `flake.nix`                            | None   | Dendritic pattern auto-discovers files                         |
| `modules/configurations/nixos.nix`     | None   | No changes needed (options available via config)               |
| `modules/system76/imports.nix`         | None   | Already imports base aggregator; receives new options          |
| `modules/home-manager/nixos.nix`       | None   | No changes needed (options available via osConfig)             |

**Comparison with original plan:**

| Original File                           | New Status | Reason                                          |
| --------------------------------------- | ---------- | ----------------------------------------------- |
| `lib/user-defaults.nix`                 | Removed    | Replaced by proper NixOS module                 |
| `modules/meta/user-defaults-validation.nix` | Merged | Assertions now in main module (Step 1.5)        |
| Multiple injection point changes       | Eliminated | Standard NixOS config access replaces injection |

## Testing Strategy

### 1. Options module validation

```bash
# Verify module syntax
nix-instantiate --parse modules/meta/user-defaults.nix

# Verify options are declared
nix eval '.#nixosConfigurations.system76.options.userDefaults.apps.type.description' 2>/dev/null && echo "Options declared"

# Verify default values are set
nix eval '.#nixosConfigurations.system76.config.userDefaults.apps.browser.windowClass'
# Expected: "firefox"
```

### 2. Type checking verification

```bash
# Verify types.package works (this should succeed)
nix eval '.#nixosConfigurations.system76.config.userDefaults.apps.browser.package.name'
# Expected output format: "firefox-<version>" (e.g., "firefox-138.0.1")
# The exact version depends on your nixpkgs pin

# Verify pname extraction works
nix eval '.#nixosConfigurations.system76.config.userDefaults.apps.browser.package.pname'
# Expected: "firefox" (just the name, no version)

# Verify type errors are caught (this should fail with clear error)
# If someone tried: userDefaults.apps.browser.package = "firefox";
# Error would be: "value is a string while a package was expected"
```

### 3. Home Manager integration (critical path)

```bash
# Test that workspace assigns are generated with correct window classes
nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.xsession.windowManager.i3.config.assigns' --json

# Expected output should contain:
# "1": [{"class": "(?i)(?:Geany)"}]
# "2": [{"class": "(?i)(?:firefox|Navigator)"}]  # Note: includes aliases
# "3": [{"class": "(?i)(?:Thunar)"}]
```

### 4. Build verification

```bash
# Full build test
nix build .#nixosConfigurations.system76.config.system.build.toplevel

# Verify no assertion failures or warnings
# (assertions from Step 1.5 should pass)

# Check specific assigns
nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.xsession.windowManager.i3.config.assigns."1"' --json
```

### 5. Override mechanism test

```bash
# Verify mkDefault allows PARTIAL overrides (per-field mkDefault)
# User can override just the package without specifying all other fields:
#   userDefaults.apps.browser.package = pkgs.brave;
# This works because mkDefault is applied to EACH FIELD, not the whole attrset

# Test that partial override preserves other defaults using nix eval
nix eval --expr '
  let
    lib = (import <nixpkgs> {}).lib;
    browser = {
      package = lib.mkDefault "firefox";
      windowClass = lib.mkDefault "firefox";
    };
    override = { package = "brave"; };  # Only override package
    merged = lib.mkMerge [ browser override ];
  in { pkg = merged.package; class = merged.windowClass; }
'
# Expected: { class = "firefox"; pkg = "brave"; }
# (package overridden, windowClass preserved from default)
```

### 6. Validation toggle test

```bash
# Verify strictValidation option exists and defaults to false
nix eval '.#nixosConfigurations.system76.config.userDefaults.strictValidation'
# Expected: false

# To test strictValidation = true behavior, temporarily add to config:
#   userDefaults.strictValidation = true;
# Then build - any package mismatches will cause assertion failures
```

### 7. WM_CLASS verification (reference)

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

### 8. Runtime verification

After deployment:

- Open Firefox → should appear on workspace 2
- Open Geany → should appear on workspace 1
- Open Thunar → should appear on workspace 3
- Verify `gui.i3.commands` override still works (set custom value, rebuild, confirm)

## Rollback Plan

If issues arise:

1. Revert i3-config.nix to hardcoded `commandsDefault` and assigns
2. Delete `modules/meta/user-defaults.nix` (module is auto-discovered, so removing the file disables it)
3. Delete `lib/user-defaults-helpers.nix`
4. No flake.nix or injection point changes needed (they were never modified)

## Dependencies

- NixOS module system (`lib.mkOption`, `types.submodule`, `types.package`)
- Dendritic pattern for file discovery (import-tree auto-imports all `.nix` files)
- Base aggregator pattern (`flake.nixosModules.base` merges contributions from multiple files)
- Home Manager `osConfig` for NixOS config access
- No flake-parts `_module.args` or `specialArgs` injection required
- No external dependencies

## Design Decisions

### Why NixOS options module instead of pure data file?

The original plan used a pure data file (`lib/user-defaults.nix`) imported before `pkgs` exists. This was changed to a proper NixOS module because:

1. **Type safety**: `types.package` catches errors at evaluation time, not runtime
2. **Direct package references**: No need for string path resolution helpers
3. **Standard patterns**: Follows `nixos-manual/development/settings-options.section.md` recommendations
4. **Auto-generated documentation**: Options appear in NixOS manual automatically
5. **Proper merge semantics**: Multiple modules can contribute to configuration

The metaOwner pattern (pure data injection) works well for static metadata, but userDefaults requires package resolution—a different use case better served by the module system.

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
   | Type      | `types.package` (actual package)           | `types.package`           |
   | Evaluated | During NixOS evaluation                    | During NixOS evaluation   |

   **Rationale:**
   - **Different concerns:** Choosing "Firefox fills the browser role" is separate from "install Firefox ESR variant"
   - **Multiple apps:** User may have Firefox (browser role) + Brave (also installed) + Chrome (also installed)
   - **Explicitness:** No magic "changing Firefox version changes my keybindings"

   **Use cases:**

   | Scenario                                 | userDefaults change                       | Module option change                                   |
   | ---------------------------------------- | ----------------------------------------- | ------------------------------------------------------ |
   | Change browser from Firefox to Brave     | `browser.package = pkgs.brave`            | Enable brave module                                    |
   | Use Firefox ESR as browser               | `browser.package = pkgs.firefox-esr`      | `programs.firefox.extended.package = pkgs.firefox-esr` |
   | Keep Firefox as default, also have Brave | No change                                 | Enable both modules                                    |

   **Coherence guarantee:** Validation assertions (Step 1.5) verify that userDefaults references installed packages.

3. ~~How should applications with multiple window classes be handled?~~ **Resolved: Use `windowClassAliases` option.**

   Applications like Firefox can appear with different WM_CLASS values depending on profile, mode, or window type:
   - `firefox` (main window)
   - `Navigator` (legacy class)
   - `firefox-default` (profile-specific)

   **Solution:** The `windowClassAliases` option (type: `types.listOf types.str`) captures additional classes:

   ```nix
   userDefaults.apps.browser = {
     package = pkgs.firefox;
     windowClass = "firefox";           # Primary class
     windowClassAliases = [ "Navigator" ];  # Additional classes to match
     desktopEntry = "firefox.desktop";
   };
   ```

   The `mkAssign` helper generates a regex that matches all classes (with proper escaping):

   ```nix
   mkAssign = role:
     let
       allClasses = getAllWindowClasses role;  # [ "firefox" "Navigator" ]
       escapedClasses = map lib.strings.escapeRegex allClasses;
     in
     { class = "(?i)(?:${lib.concatStringsSep "|" escapedClasses})"; };
   # Result: { class = "(?i)(?:firefox|Navigator)"; }
   ```

   **Finding WM_CLASS values:** Run `xprop WM_CLASS` and click each application window to discover all classes an app uses.

4. ~~How should validation handle packages where pname ≠ module namespace?~~ **Resolved: Use `moduleName` option.**

   Some packages have a `pname` that doesn't match the `programs.*` module namespace:
   - `pkgs.firefox-esr` has pname `"firefox"` but module might be `programs.firefox-esr.extended`
   - `pkgs.google-chrome` has pname `"google-chrome"` but no matching module may exist

   **Solution:** The `moduleName` option allows explicit override:

   ```nix
   userDefaults.apps.browser = {
     package = pkgs.firefox-esr;
     windowClass = "firefox";
     desktopEntry = "firefox.desktop";
     moduleName = "firefox";  # Validates against programs.firefox.extended
   };
   ```

   When `moduleName` is `null` (default), the module name is derived from `package.pname`.
   The validation helper uses `lib.hasAttrByPath` for safe existence checking and includes
   the `hasModule` flag in results to enable accurate warning generation.

5. ~~What about standalone Home Manager deployments?~~ **Resolved: Not supported (documented constraint).**

   The `osConfig` dependency means this system only works when Home Manager is configured
   as a NixOS module. This is documented as an architectural constraint in the module header.
   For this repository (single NixOS host), this limitation is acceptable.
