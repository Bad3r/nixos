# Application Modules Refactoring

This directory contains tools for refactoring application modules to follow NixOS best practices.

## Status

**Branch**: `refactor/standardize-app-modules`

### Completed (Phase 0 - Preparation)

- ✅ Created refactor branch and directory structure
- ✅ Created 3 module templates (simple, unfree, multi-package)
- ✅ Implemented transformation script (`transform-module.sh`)
- ✅ Implemented batch transformation script (`batch-transform.sh`)
- ✅ **Pilot: Successfully converted 7 modules**:
  - firefox.nix
  - brave.nix (unfree)
  - wget.nix
  - jq.nix
  - git.nix
  - curl.nix
  - vim.nix
- ✅ Validated all pilot modules (syntax correct, flake evaluates)

### Remaining Work

#### Phase 1: Bulk Transformation (~2-3 hours)

```bash
# Dry-run to preview changes
./scripts/refactor/batch-transform.sh --dry-run

# Execute transformation
./scripts/refactor/batch-transform.sh

# Review output
cat scripts/refactor/output/failed.txt  # Check for failures
```

#### Phase 2: Testing (~1-2 hours)

- Generate tests for all modules
- Run `nix flake check`
- Build system76 configuration
- Validate no closure size changes

#### Phase 3: Documentation (~1 hour)

- Update CLAUDE.md with module authoring guidelines
- Create pre-commit hook
- Write commit message

#### Phase 4: Review & Merge (~1 hour)

- Code review
- Final validation
- Merge to main

## Tools

### transform-module.sh

Transforms a single module to proper NixOS structure.

**Usage**:

```bash
./scripts/refactor/transform-module.sh <module-path> <category> [--dry-run]
```

**Categories**:

- `simple`: Basic package installation
- `unfree`: Requires allowUnfreePredicate
- `multi-package`: Multiple related packages
- `skip`: Already has proper structure

**Example**:

```bash
# Dry-run (preview only)
./scripts/refactor/transform-module.sh modules/apps/firefox.nix simple --dry-run

# Live transformation
./scripts/refactor/transform-module.sh modules/apps/firefox.nix simple
```

### batch-transform.sh

Batch transforms all remaining modules.

**Usage**:

```bash
# Preview what will change
./scripts/refactor/batch-transform.sh --dry-run

# Execute transformations
./scripts/refactor/batch-transform.sh
```

**Features**:

- Automatically skips already-converted modules
- Detects unfree packages
- Validates syntax
- Generates statistics

## Templates

Located in `scripts/refactor/templates/`:

- **simple.nix.template**: Standard application module
- **unfree.nix.template**: Application requiring unfree license
- **multi-package.nix.template**: Application with extra packages

## Module Structure

All transformed modules follow this pattern:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.<name>.extended;
  <Name>Module = {
    options.programs.<name>.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;  # Backward compatibility
        description = lib.mdDoc "Whether to enable <name>.";
      };

      package = lib.mkPackageOption pkgs "<name>" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.<name> = <Name>Module;
}
```

## Validation

Check that transformations worked:

```bash
# Syntax validation
for f in modules/apps/{firefox,brave,wget,jq,git,curl,vim}.nix; do
  nix-instantiate --parse "$f" && echo "✓ $f" || echo "✗ $f"
done

# Full flake check
nix flake check --accept-flake-config
```

## Next Steps

1. **Run batch transformation** on remaining ~235 modules
2. **Create tests** for enable/disable behavior
3. **Validate** with `nix flake check` and system76 build
4. **Update documentation** in CLAUDE.md
5. **Create pre-commit hook** to enforce pattern
6. **Review and merge**

## Reference

- **Implementation Plan**: See anti-pattern analysis report
- **NixOS Documentation**: `nixos_docs_md/420_writing_nixos_modules.md`
- **Example Modules**:
  - Simple: `modules/apps/firefox.nix` (post-refactor)
  - Unfree: `modules/apps/brave.nix` (post-refactor)
  - Complex: `modules/apps/steam.nix`, `modules/apps/mangohud.nix`
