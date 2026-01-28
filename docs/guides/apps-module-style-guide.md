# Apps Module Style Guide

This guide defines the expectations for `modules/apps/<tool>.nix` files. Use it alongside `modules/apps/ent.nix`, which serves as the canonical template, and refer to [`docs/architecture/`](../architecture/) for the bigger-picture aggregator and helper context.

## Source Gathering

- Before editing a module header, confirm every fact from an authoritative source.
- Start by inspecting the pinned nixpkgs expression for the package to capture `description`, `homepage`, current version, and upstream repository metadata.
- Use Context7 documentation fetches, DeepWiki repository insights, or an online search to cross-check details with official project documentation. Prioritize primary sources (project docs, release notes, upstream repository README).
- Identify the canonical user manual or API reference and verify that the URL resolves (follow redirects when necessary). Prefer HTTPS endpoints maintained by the project owner.
- Document which source satisfied each field in your working notes so reviewers can replay the lookup if needed.

## External Flake Input Packages

When adding packages from external flake inputs (e.g., `llm-agents.nix`) instead of nixpkgs:

### Discovery & Verification

```bash
# List available packages in the flake
nix eval github:org/repo#packages.x86_64-linux --apply builtins.attrNames

# Check package metadata
nix eval github:org/repo#packages.x86_64-linux.<name>.meta.description --raw
nix eval github:org/repo#packages.x86_64-linux.<name>.meta.homepage --raw
```

### Module Structure Differences

- **Outer module signature**: Use `{ inputs, ... }:` instead of `_:` to access flake inputs
- **Package option pattern**:
  ```nix
  package = lib.mkOption {
    type = lib.types.package;
    default = inputs.<flake-name>.packages.${pkgs.stdenv.hostPlatform.system}.<package-name>;
    defaultText = lib.literalExpression "inputs.<flake-name>.packages.\${system}.<package-name>";
    description = "The <package-name> package to use.";
  };
  ```
- **Notes section**: Always document the source flake in the header's `Notes:` section

### Example

See `modules/apps/claude-code.nix`, `modules/apps/spec-kit.nix`, or `modules/apps/codex.nix` for complete examples.

## Scope

- Applies to every NixOS app module exported under `flake.nixosModules.apps`.
- Complements the repository-wide conventions noted in [`docs/architecture/02-module-authoring.md`](../architecture/02-module-authoring.md).

## File Layout

- Store each app module at `modules/apps/<tool>.nix`.
- Export the module as `flake.nixosModules.apps.<tool>`. Provide additional bundles (for example `workstation`, `base`) only when they are meaningful.
- Keep per-app modules focused on package enablement and lightweight configuration. Compose higher-level behaviour in domain modules (for example `modules/networking/`).

## Top-of-File Documentation Block

- Start every file with a C-style block comment: `/* ... */`.
- Populate the header in this order:
  - `Package:` -- the app name matching the filename.
  - `Description:` -- one-sentence summary.
  - `Homepage:` -- primary product landing page.
  - `Documentation:` -- canonical manual, user guide, or reference docs. Prefer first-party sources; if none exist, use the section of the homepage that acts as official documentation.
  - `Repository:` -- upstream GitHub project URL when available. Omit only if no public GitHub repository exists.
- Provide the following subsections, each separated by a blank line:
  - `Summary:` -- two bullet points describing primary functionality.
  - `Tests:` -- only include when upstream documents deterministic CLI outputs (for example `ent.nix`). If no canonical tests exist, omit the section completely rather than inventing ad-hoc commands.
  - `Options:` -- bullet list covering notable flags, switches, or usage notes. Use `-flag` entries to mirror CLI flags and keep bullets to one line each. Reference official command documentation when paraphrasing behaviour.
  - `Notes:` -- optional section for module-specific implementation details. Use when the module delegates responsibilities (e.g., package installation handled by Home Manager) or has namespace considerations (e.g., uses `services` instead of `programs`). Omit for straightforward modules.
- Bullet style inside the comment:
  - Use `*` for generic bullet points (`Summary`, `Tests`, `Notes`).
  - Use the literal option token (for example `-b`) as the bullet for `Options`, as shown in `ent.nix`.
- When documenting CLI options:
  - For flag-based tools: Use literal flags (`-f`, `--verbose`) as bullet markers
  - For subcommand-based tools: Use subcommand names (`init`, `generate`, `onboard`)
  - For tools with minimal CLI: Document what exists, even if only 1-2 items
  - For GUI or daemon tools: Document configuration patterns or notable behaviors instead
- Unicode characters are acceptable; retain the form used by upstream documentation (for example `π` in statistical descriptions).
- When a project offers multiple front-ends (for example CLI and GUI), scope the comment to the component delivered by the package.

## Module Body

- For nixpkgs packages: The outer flake-parts module takes `_:` (ignores its config argument)
- For external flake inputs: Use `{ inputs, ... }:` to access flake inputs
- Define the NixOS module as a function inside a `let` binding with `{ config, lib, pkgs, ... }:`
- Place `cfg = config.programs.<tool>.extended;` inside the NixOS module function (not the outer scope)
- Prefer `environment.systemPackages = [ cfg.package ];` for package exposure
- Limit additional configuration to essentials required for the app to function
- Maintain two-space indentation for attribute sets

## Example Skeleton

```nix
/*
  Package: example
  Description: Short explanation.
  Homepage: https://example.org
  Documentation: https://docs.example.org/cli
  Repository: https://github.com/example/example

  Summary:
    * Key capability line one.
    * Key capability line two.

  Options:
    -f: Important flag summary.
    -q: Another flag.
*/
_:
let
  ExampleModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.example.extended;
    in
    {
      options.programs.example.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable example.";
        };

        package = lib.mkPackageOption pkgs "example" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.example = ExampleModule;
}
```

## Example Skeleton (External Flake Input)

```nix
/*
  Package: example
  Description: Short explanation.
  Homepage: https://example.org
  Documentation: https://docs.example.org/cli
  Repository: https://github.com/example/example

  Summary:
    * Key capability line one.
    * Key capability line two.

  Options:
    -f: Important flag summary.
    -q: Another flag.

  Notes:
    * Package sourced from example-flake (github:org/example-flake).
*/
{ inputs, ... }:
{
  flake.nixosModules.apps.example =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.example.extended;
    in
    {
      options.programs.example.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable example.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.example-flake.packages.${pkgs.stdenv.hostPlatform.system}.example;
          defaultText = lib.literalExpression "inputs.example-flake.packages.\${system}.example";
          description = "The example package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
```

## Namespace Selection

Most apps use `programs.<name>.extended`. However, apps requiring NixOS services (udev, systemd) use `services.<name>.extended` instead.

| Namespace                  | When to Use                                          | Enable in apps-enable.nix |
| -------------------------- | ---------------------------------------------------- | ------------------------- |
| `programs.<name>.extended` | Package-only apps                                    | `programs` block          |
| `services.<name>.extended` | Apps with NixOS service (e.g., `services.autorandr`) | `services` block          |

The module pattern is identical--just substitute `programs` with `services` in option paths.

## Maintenance Checklist

- When adding a new app module, copy the skeleton, update the comment sections, and adjust bundles as required.
- Note the primary source used for each header field (nixpkgs, upstream docs, release notes).
- Run `nix fmt` after edits to preserve formatting.
- Review the header comment whenever options change or new capabilities ship to keep the documentation truthful.
- Before pushing, run the full validation suite per [`docs/architecture/06-reference.md`](../architecture/06-reference.md#validation).

## Complete Workflow Checklist

When adding a new app, complete each step in order:

### 1. Verify Package Availability

**For nixpkgs packages**:

```bash
# Check package exists and isn't deprecated/aliased
nix eval nixpkgs#<name>.meta.description --raw

# If you get an error about aliases, check the actual package name
nix eval nixpkgs#<name> --raw 2>&1
```

**For external flake input packages**:

```bash
# List available packages
nix eval github:org/repo#packages.x86_64-linux --apply builtins.attrNames

# Verify package exists and check metadata
nix eval github:org/repo#packages.x86_64-linux.<name>.meta.description --raw
nix eval github:org/repo#packages.x86_64-linux.<name>.meta.homepage --raw
```

Some packages have different names (e.g., `floorp` is deprecated → use `floorp-bin`).

### 2. Create NixOS Module

- Create `modules/apps/<tool>.nix` following the skeleton above.
- Use `lib.mkPackageOption pkgs "<actual-pkg-name>" { }` with the correct package name.

### 3. Stage New Files (Critical)

```bash
git add modules/apps/<tool>.nix
```

> **Pitfall:** `nix flake check` copies only git-tracked files to the Nix store. Untracked files are invisible to the flake and will cause "option does not exist" errors.

### 4. Enable in apps-enable.nix

Add to `modules/system76/apps-enable.nix` in alphabetical order:

```nix
programs = {
  # ...
  <tool>.extended.enable = lib.mkOverride 1100 true;
  # ...
};
```

### 5. Check for Home Manager Integration

```bash
# Check local mirror
ls "~/git/home-manager/modules/programs/<tool>.nix"

# Or search for the program
grep -r "programs\.<tool>" ~/git/home-manager/modules/programs/
```

If HM support exists, continue to step 6. Otherwise, skip to step 8.

### 6. Create Home Manager Module

Create `modules/hm-apps/<tool>.nix`. HM modules **must** guard against enabling when the corresponding NixOS module is disabled.

**Before writing the module**, check if the HM module's package option is nullable:

```bash
grep -A3 "package.*=" ~/git/home-manager/modules/programs/<tool>.nix
# Look for: nullable = true;
```

```nix
/*
  Package: <tool>
  Description: ...
  Homepage: ...
  ...
*/

_: {
  flake.homeManagerModules.apps.<tool> =
    { osConfig, lib, ... }:
    let
      # Safe nested attribute access - required pattern
      nixosEnabled = lib.attrByPath
        [ "programs" "<tool>" "extended" "enable" ]
        false
        osConfig;
    in
    {
      # Guard config with mkIf to delay evaluation
      config = lib.mkIf nixosEnabled {
        programs.<tool> = {
          enable = true;
          package = null;
        };
      };
    };
}
```

**Package Installation Pattern:**

| HM package option | Action                                                                       |
| ----------------- | ---------------------------------------------------------------------------- |
| `nullable = true` | Use `package = null;` -- NixOS module installs the package                   |
| Not nullable      | Omit `package` -- HM will use default, NixOS also installs (same store path) |
| No package option | Omit `package` -- HM only manages config                                     |

> **Exceptions:** Some HM modules require the package reference for additional features (e.g., `bun` needs it for `enableGitIntegration` to configure git diff). In such cases, omit `package = null` and add a comment explaining why:
>
> ```nix
> # NOTE: Cannot use `package = null` here because <feature>
> # requires the package reference to <reason>.
> ```

> **Required:** All HM modules that depend on NixOS module enablement **must** use `lib.attrByPath` for safe nested attribute access and `lib.mkIf` to guard the config block. See [NixOS-HM Dependency Guard Pattern](#nixos-hm-dependency-guard-pattern) for details.

### 7. Add to Home Manager Imports

Add to `modules/system76/home-manager-apps.nix` in the `extraAppNames` list:

```nix
extraAppNames = [
  # ...
  "<tool>"
  # ...
];
```

> **Pitfall:** HM modules exported to `flake.homeManagerModules.apps.<name>` are **not** auto-imported. They must be explicitly listed in `home-manager-apps.nix`. The `flake.homeManagerModules.gui` namespace (used by i3wm, terminal configs, etc.) is auto-loaded separately.

### 8. Check for Stylix Integration

```bash
# Check if stylix supports the app
grep -r "<tool>" ~/git/stylix/modules/
```

### 9. Add Stylix Configuration (if supported)

Add to `modules/style/stylix.nix` under `flake.homeManagerModules.gui`:

```nix
stylix.targets.<tool> = {
  colorTheme.enable = true;
  # ... other options
};
```

### 10. Stage All Files and Validate

```bash
git add modules/apps/<tool>.nix modules/hm-apps/<tool>.nix
git add modules/system76/apps-enable.nix
git add modules/system76/home-manager-apps.nix
git add modules/style/stylix.nix

nix fmt
nix flake check --accept-flake-config --no-build

# Additional verification (optional but recommended)
nix eval .#nixosConfigurations.system76.options.programs.<tool>.extended.enable.type --raw  # Should output "bool"
nix eval .#nixosConfigurations.system76.config.programs.<tool>.extended.enable 2>&1 | tail -1  # Should output "true"
nix eval .#nixosConfigurations.system76.config.environment.systemPackages --apply 'pkgs: builtins.any (p: p.pname or "" == "<tool>") pkgs' 2>&1 | tail -1  # Should output "true"
```

## Common Pitfalls

### Git Tracking Requirement

**Problem:** `nix flake check` fails with "option does not exist" for a module you just created.

**Cause:** Flakes copy the git tree to `/nix/store`, including only tracked (staged or committed) files. Untracked files are ignored.

**Solution:** Always `git add` new files before running `nix flake check`.

### Flake-Parts vs NixOS Config Scope

**Problem:** Build fails with "attribute 'programs' missing" when accessing `config.programs.<tool>.extended`.

**Cause:** The outer flake-parts module receives flake-parts config (which has no `programs` attribute). Using `{ config, lib, pkgs, ... }:` at the outer scope binds `config` to flake-parts config, not NixOS config.

```nix
# WRONG - config is flake-parts config, not NixOS config
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.tool.extended;  # ERROR: programs doesn't exist
  ToolModule = { ... };
in
{
  flake.nixosModules.apps.tool = ToolModule;
}

# CORRECT - NixOS module receives NixOS config
_:
let
  ToolModule =
    {
      config,  # This is NixOS config
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tool.extended;  # Works correctly
    in
    { ... };
in
{
  flake.nixosModules.apps.tool = ToolModule;
}
```

**Solution:** Use `_:` for the outer flake-parts module and define the NixOS module function inside a `let` binding.

### NixOS-HM Dependency Guard Pattern

**Problem:** HM module uses `osConfig.programs.<tool>.extended.enable or false` but fails with "attribute 'extended' missing".

**Cause:** Nix's `or` operator only catches missing attributes at the **final** level. If any intermediate path segment is missing, evaluation fails before `or` is reached.

```nix
# WRONG - fragile pattern
osConfig.programs.<tool>.extended.enable or false
# Fails if .extended doesn't exist (only catches missing .enable)

# CORRECT - safe pattern
lib.attrByPath [ "programs" "<tool>" "extended" "enable" ] false osConfig
# Safely traverses any depth with fallback
```

**Required pattern for HM modules:**

```nix
{ osConfig, lib, ... }:
let
  nixosEnabled = lib.attrByPath
    [ "programs" "<tool>" "extended" "enable" ]
    false
    osConfig;
in
{
  config = lib.mkIf nixosEnabled {
    programs.<tool>.enable = true;
  };
}
```

**Why both `lib.attrByPath` AND `lib.mkIf` are required:**

| Component        | Purpose                                                                               |
| ---------------- | ------------------------------------------------------------------------------------- |
| `lib.attrByPath` | Safely access nested attributes without evaluation errors                             |
| `lib.mkIf`       | Delay config evaluation to avoid infinite recursion (per NixOS module best practices) |

This pattern aligns with CLAUDE.md guidance: "Use `lib.hasAttrByPath` + `lib.getAttrFromPath` for optional modules to avoid ordering issues."

## Integration Discovery Reference

### Home Manager

| Check               | Command                                                                 |
| ------------------- | ----------------------------------------------------------------------- |
| Module exists       | `ls ~/git/home-manager/modules/programs/<tool>.nix`                     |
| Search by name      | `grep -r "programs\.<tool>" ~/git/home-manager/modules/`                |
| Firefox derivatives | Check `~/git/home-manager/modules/programs/firefox/mkFirefoxModule.nix` |

### Stylix

| Check                    | Command                                   |
| ------------------------ | ----------------------------------------- |
| General support          | `grep -r "<tool>" ~/git/stylix/modules/`  |
| Firefox/Floorp/LibreWolf | `cat ~/git/stylix/modules/firefox/hm.nix` |
| Available options        | `cat ~/git/stylix/modules/<tool>/`        |

### NUR Firefox Addons

| Check        | Command                                                                      |
| ------------ | ---------------------------------------------------------------------------- |
| List addons  | `nix eval nixpkgs#nur.repos.rycee.firefox-addons --apply builtins.attrNames` |
| Search addon | `nix search nixpkgs#nur.repos.rycee.firefox-addons.<name>`                   |
