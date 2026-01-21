# Migration Plan: pre-commit (git-hooks.nix) to lefthook

## Overview

Replace the `git-hooks.nix` flake module (cachix/git-hooks.nix) with lefthook, a single Go binary. This migration preserves 10 hooks (detect-private-keys merged into ripsecrets, trim-trailing-whitespace covered by treefmt) while gaining:

- Native parallel execution
- No Python runtime dependency
- Static `lefthook.yml` committed to repo
- Faster hook startup (Go binary vs Python)

### Idiomatic Nix Approach

Hook scripts are implemented as **Nix derivations** using `writeShellApplication`, NOT static shell files. This ensures:

- **Explicit dependency declaration** via `runtimeInputs`
- **PATH isolation** - scripts use only declared dependencies
- **Build-time verification** - missing deps fail the build, not runtime
- **Reproducibility** - identical behavior across all environments

Scripts are exposed as packages in `modules/meta/lefthook.nix` and referenced by executable name in `lefthook.yml`.

---

## Files to Create

### 1. `modules/meta/lefthook.nix` (Nix-wrapped hook scripts)

This flake-parts module defines hook scripts as `writeShellApplication` derivations with explicit dependencies:

```nix
_:
{
  perSystem =
    { pkgs, config, ... }:
    let
      # === Nix-Wrapped Hook Scripts ===

      lefthookTreefmt = pkgs.writeShellApplication {
        name = "lefthook-treefmt";
        runtimeInputs = [
          config.treefmt.build.wrapper
          pkgs.git
          pkgs.coreutils
          pkgs.util-linux # flock
        ];
        text = /* bash */ ''
          # Caching and locking for treefmt
          cache_root="''${TREEFMT_CACHE_ROOT:-$PWD/.git/treefmt-cache}"
          if ! mkdir -p "''${cache_root}" 2>/dev/null; then
            cache_root="''${TMPDIR:-/tmp}/treefmt-cache"
            mkdir -p "''${cache_root}"
          fi

          cache_home="''${cache_root}/cache"
          mkdir -p "''${cache_home}"

          lock_file="''${cache_root}/cache.lock"
          lock_timeout="''${TREEFMT_CACHE_TIMEOUT:-30}"

          exec 9>"''${lock_file}"
          if ! flock -w "''${lock_timeout}" 9; then
            echo "treefmt: failed to acquire cache lock within ''${lock_timeout}s" >&2
            exit 1
          fi
          trap 'flock -u 9' EXIT

          export TREEFMT_CACHE_DB="''${cache_home}/eval-cache"

          # Get ALL modified files (staged + unstaged), excluding symlinks to nix store
          # This ensures consistency - format everything that's changed from HEAD
          mapfile -t modified < <(git diff HEAD --name-only --diff-filter=ACM | while read -r f; do
            if [ -L "$f" ]; then
              target=$(readlink -f "$f" 2>/dev/null || true)
              case "$target" in /nix/store/*) continue ;; esac
            fi
            printf '%s\n' "$f"
          done)

          if [ "''${#modified[@]}" -eq 0 ]; then
            exit 0
          fi

          err_file=$(mktemp)
          trap 'rm -f "$err_file"; flock -u 9' EXIT

          if ! treefmt "''${modified[@]}" >/dev/null 2>"$err_file"; then
            echo "treefmt: formatting failed - manual fix required:" >&2
            cat "$err_file" >&2
            exit 1
          fi
        '';
      };

      lefthookStatix = pkgs.writeShellApplication {
        name = "lefthook-statix";
        runtimeInputs = [
          pkgs.statix
          pkgs.coreutils
        ];
        text = /* bash */ ''
          status=0
          if [ "$#" -eq 0 ]; then
            statix check --format errfmt || status=$?
            exit $status
          fi
          for f in "$@"; do
            if [ -f "$f" ]; then
              statix check --format errfmt "$f" || status=$?
            fi
          done
          exit $status
        '';
      };

      lefthookEnsureSops = pkgs.writeShellApplication {
        name = "lefthook-ensure-sops";
        runtimeInputs = [ pkgs.pre-commit-hook-ensure-sops ];
        text = /* bash */ ''
          [ $# -eq 0 ] && exit 0
          exec pre-commit-hook-ensure-sops "$@"
        '';
      };

      lefthookManagedFilesDrift = pkgs.writeShellApplication {
        name = "lefthook-managed-files-drift";
        runtimeInputs = [
          pkgs.git
          pkgs.coreutils
          pkgs.diffutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.gawk
        ];
        text = /* bash */ ''
          root=$(git rev-parse --show-toplevel)
          cd "$root"

          if ! command -v write-files >/dev/null 2>&1; then
            exit 0
          fi

          writer=$(command -v write-files)
          mapfile -t pairs < <(grep -E '^cat /nix/store/.+ > .+$' "$writer" || true)

          if [ "''${#pairs[@]}" -eq 0 ]; then
            exit 0
          fi

          drift=0
          AUTO_FIX="''${AUTO_FIX_MANAGED:-1}"
          VERBOSE="''${MANAGED_FILES_VERBOSE:-0}"
          declare -a update_paths=()

          for line in "''${pairs[@]}"; do
            src=$(printf '%s' "$line" | awk '{print $2}')
            dst_rel=$(printf '%s' "$line" | sed -E 's/^.*>\s*//')
            dst="$root/$dst_rel"

            if [ ! -f "$dst" ]; then
              if [ "$AUTO_FIX" != 1 ] || [ "$VERBOSE" = 1 ]; then
                echo "✗ Missing managed file: $dst_rel" >&2
              fi
              drift=1
              update_paths+=("$dst_rel")
              continue
            fi

            if ! cmp -s "$src" "$dst"; then
              if [ "$AUTO_FIX" != 1 ] || [ "$VERBOSE" = 1 ]; then
                echo "✗ Drift detected: $dst_rel" >&2
                diff -u --label "$dst_rel(expected)" "$src" --label "$dst_rel" "$dst" | sed 's/^/    /' || true
              fi
              drift=1
              update_paths+=("$dst_rel")
            fi
          done

          if [ "$drift" -ne 0 ]; then
            if [ "''${#update_paths[@]}" -gt 0 ]; then
              write-files >/dev/null
              git add "''${update_paths[@]}" 2>/dev/null || true

              if [ "$AUTO_FIX" = 1 ]; then
                GIT_COMMITTER_DATE="$(date -u -R)" \
                GIT_AUTHOR_DATE="$(date -u -R)" \
                git -c core.hooksPath=/dev/null commit --no-verify \
                  -m "chore(managed): refresh generated files" "''${update_paths[@]}" >/dev/null 2>&1 || true
              else
                if [ "$VERBOSE" = 1 ]; then
                  echo "Run: write-files, then commit the changes." >&2
                fi
                exit 1
              fi
            fi
            exit 0
          fi
        '';
      };

      lefthookAppsCatalogSync = pkgs.writeShellApplication {
        name = "lefthook-apps-catalog-sync";
        runtimeInputs = [
          pkgs.git
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.gawk
          pkgs.findutils
        ];
        text = /* bash */ ''
          root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
          cd "$root"

          apps_dir="modules/apps"
          catalog_file="modules/system76/apps-enable.nix"

          excluded_apps=(
            "qemu"
            "vmware-workstation"
            "ovftool"
          )

          should_run=0
          if git diff --cached --name-status --diff-filter=AD | grep -q "^[AD].*$apps_dir/.*\.nix$"; then
            should_run=1
          fi
          if git diff --cached --name-only | grep -q "^$catalog_file$"; then
            should_run=1
          fi
          if [ "$should_run" -eq 0 ]; then
            exit 0
          fi

          mapfile -t filesystem_apps < <(
            find "$apps_dir" -maxdepth 1 -type f -name "*.nix" ! -name "_*.nix" -printf "%f\n" \
              | sed 's/\.nix$//' \
              | sort
          )

          declare -A excluded_map
          for excluded in "''${excluded_apps[@]}"; do
            excluded_map["$excluded"]=1
          done

          declare -a filtered_fs_apps=()
          for app in "''${filesystem_apps[@]}"; do
            if [ -z "''${excluded_map[$app]:-}" ]; then
              filtered_fs_apps+=("$app")
            fi
          done
          filesystem_apps=("''${filtered_fs_apps[@]}")

          mapfile -t catalog_apps < <(
            grep -E '\.extended\.enable' "$catalog_file" \
              | sed -E 's/^\s+//' \
              | sed -E "s/^([\"']?)([a-zA-Z0-9_-]+)\1\.extended\.enable.*/\2/" \
              | sort
          )

          declare -A fs_map catalog_map
          for app in "''${filesystem_apps[@]}"; do
            fs_map["$app"]=1
          done
          for app in "''${catalog_apps[@]}"; do
            catalog_map["$app"]=1
          done

          declare -a missing=()
          for app in "''${filesystem_apps[@]}"; do
            if [ -z "''${catalog_map[$app]:-}" ]; then
              missing+=("$app")
            fi
          done

          declare -a stale=()
          for app in "''${catalog_apps[@]}"; do
            if [ -z "''${fs_map[$app]:-}" ]; then
              stale+=("$app")
            fi
          done

          if [ "''${#missing[@]}" -gt 0 ] || [ "''${#stale[@]}" -gt 0 ]; then
            echo "" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "❌ Error: apps-enable.nix is out of sync with modules/apps/" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2

            if [ "''${#missing[@]}" -gt 0 ]; then
              echo "📝 Missing entries (add these to $catalog_file):" >&2
              echo "" >&2
              for app in "''${missing[@]}"; do
                if [[ "$app" =~ - ]]; then
                  echo "  \"$app\".extended.enable = lib.mkOverride 1100 false;" >&2
                else
                  echo "  $app.extended.enable = lib.mkOverride 1100 false;" >&2
                fi
              done
              echo "" >&2
            fi

            if [ "''${#stale[@]}" -gt 0 ]; then
              echo "🗑️  Stale entries (remove these from $catalog_file):" >&2
              echo "" >&2
              for app in "''${stale[@]}"; do
                if [[ "$app" =~ - ]]; then
                  line_num=$(grep -n "\"$app\"\.extended\.enable" "$catalog_file" | cut -d: -f1 || echo "?")
                else
                  line_num=$(grep -n "$app\.extended\.enable" "$catalog_file" | cut -d: -f1 || echo "?")
                fi
                echo "  $app (line $line_num)" >&2
              done
              echo "" >&2
            fi

            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "ℹ️  Summary:" >&2
            echo "   Filesystem: ''${#filesystem_apps[@]} apps" >&2
            echo "   Catalog:    ''${#catalog_apps[@]} apps" >&2
            echo "   Missing:    ''${#missing[@]} entries" >&2
            echo "   Stale:      ''${#stale[@]} entries" >&2
            if [ "''${#excluded_apps[@]}" -gt 0 ]; then
              echo "   Excluded:   ''${#excluded_apps[@]} apps (managed by specialized modules)" >&2
            fi
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2
            exit 1
          fi
        '';
      };
    in
    {
      packages = {
        inherit
          lefthookTreefmt
          lefthookStatix
          lefthookEnsureSops
          lefthookManagedFilesDrift
          lefthookAppsCatalogSync
          ;
      };
    };
}
```

**Package summary:**

| Package                     | Binary Name                    | runtimeInputs                                    |
| --------------------------- | ------------------------------ | ------------------------------------------------ |
| `lefthookTreefmt`           | `lefthook-treefmt`             | treefmt, git, coreutils, util-linux              |
| `lefthookStatix`            | `lefthook-statix`              | statix, coreutils                                |
| `lefthookEnsureSops`        | `lefthook-ensure-sops`         | pre-commit-hook-ensure-sops                      |
| `lefthookManagedFilesDrift` | `lefthook-managed-files-drift` | git, coreutils, diffutils, gnugrep, gnused, gawk |
| `lefthookAppsCatalogSync`   | `lefthook-apps-catalog-sync`   | git, coreutils, gnugrep, gnused, gawk, findutils |

---

### 2. `lefthook.yml` (repo root)

References Nix-wrapped executables by name (they're in PATH via devshell):

```yaml
# Git hooks manager - https://lefthook.dev/
min_version: 1.10.0
glob_matcher: doublestar # Standard glob behavior (** matches 0+ dirs)

# Output configuration - show only essential info
output:
  - meta
  - summary
  - failure
  - success

pre-commit:
  parallel: true
  skip: [merge, rebase] # Skip all hooks during merge/rebase to avoid conflicts
  fail_on_changes: ci # Fail in CI if hooks modify files (works with stage_fixed)

  jobs:
    # === Validation Group (priority 1 - fast checks first) ===
    # Quick syntax validation runs first to fail fast on obvious errors
    - name: validation
      priority: 1
      exclude:
        - "inputs/**"
        - "nixos-manual/**"
      group:
        parallel: true
        jobs:
          - name: check-yaml
            tags: [validation]
            run: yamllint -d relaxed -- {staged_files}
            glob: "**/*.{yaml,yml}"
            fail_text: "Invalid YAML syntax. Check errors above."

          - name: check-json
            tags: [validation]
            run: jq empty {staged_files}
            glob: "**/*.json"
            fail_text: "Invalid JSON syntax. Validate with: jq . <file>"

    # === Security Group (priority 2 - catch secrets early) ===
    # Note: ripsecrets covers private keys (RSA, DSA, EC, OpenSSH, PGP, PuTTY, SSH2, AGE)
    # Only missing: BEGIN ENCRYPTED PRIVATE KEY, BEGIN OpenVPN Static key V1 (edge cases)
    - name: security
      priority: 2
      exclude:
        - "inputs/**"
        - "nixos-manual/**"
      group:
        parallel: true
        jobs:
          - name: ripsecrets
            tags: [security]
            run: ripsecrets -- {staged_files}
            exclude:
              - "modules/networking/networking.nix" # Contains public minisign key
            fail_text: "Secrets/keys detected! Remove sensitive data or add to .secretsignore"

          - name: ensure-sops
            tags: [security]
            run: lefthook-ensure-sops {staged_files} # Nix-wrapped
            glob: "secrets/**/*.{yaml,yml,json,env,ini,age,enc}"
            fail_text: "Secrets must be SOPS-encrypted. Run: sops <file>"

    # === Formatting Group (priority 3) ===
    # Note: only root, glob, exclude, and env are inherited by group jobs
    - name: formatting
      priority: 3
      exclude:
        - "inputs/**"
        - "nixos-manual/**"
      group:
        parallel: true
        jobs:
          - name: treefmt
            tags: [formatting]
            run: lefthook-treefmt # Nix-wrapped executable
            fail_text: "Formatting failed. Check syntax errors above, then run: nix fmt"

    # === Nix Linting Group (priority 4) ===
    - name: nix-linting
      priority: 4
      glob: "**/*.nix"
      exclude:
        - "inputs/**"
        - "nixos-manual/**"
      group:
        parallel: true
        jobs:
          - name: deadnix
            tags: [nix]
            run: deadnix --fail -- {staged_files}
            fail_text: "Unused code detected. Remove dead bindings shown above."

          - name: statix
            tags: [nix]
            run: lefthook-statix {staged_files} # Nix-wrapped, receives files as args
            fail_text: "Nix anti-patterns found. Run: statix fix <file>"

    # === Quality Group (priority 5) ===
    - name: quality
      priority: 5
      exclude:
        - "inputs/**"
        - "nixos-manual/**"
      group:
        jobs:
          - name: typos
            tags: [quality]
            run: typos --config .typos.toml -- {staged_files}
            fail_text: "Typos detected. Run: typos -w <file> to fix, or add to .typos.toml"

    # === Custom Hooks Group (priority 6 - runs last) ===
    - name: custom
      priority: 6
      group:
        jobs:
          - name: managed-files-drift
            tags: [custom]
            run: lefthook-managed-files-drift # Nix-wrapped
            env:
              AUTO_FIX_MANAGED: "1" # Auto-fix and commit drifted files
              MANAGED_FILES_VERBOSE: "0" # Set to "1" for detailed diff output
            fail_text: "Managed files out of sync. Run: nix develop -c write-files"

          - name: apps-catalog-sync
            tags: [custom]
            run: lefthook-apps-catalog-sync # Nix-wrapped
            fail_text: "apps-enable.nix out of sync with modules/apps/. See errors above."
```

**Key Configuration Features:**

- `min_version: 1.10.0` - Ensures lefthook version supports jobs syntax
- `output: [meta, summary, failure, success]` - Cleaner output, only shows what matters
- `fail_on_changes: ci` - Fails in CI if hooks modify files (ensures code is pre-formatted)
- `fail_text` on all jobs - Actionable error messages guide users to fix issues
- `skip: [merge, rebase]` at hook level - Skips all hooks during merge/rebase (not inherited by groups)
- `priority` on groups - Orders job execution (1=first, 0=last): validation → security → formatting → nix → quality → custom
- **Groups with inherited `exclude`** - DRY pattern (only root, glob, exclude, and env are inherited - NOT tags, skip, etc.)
- **Tags on individual jobs** - Tags must be on each job, not parent groups
- `env` for configuration - Environment variables documented inline (e.g., managed-files-drift)
- `--` separator in commands - Safe handling of filenames starting with `-`

**Available tags for selective execution:**

- `formatting` - treefmt
- `nix` - deadnix, statix
- `quality` - typos
- `security` - ripsecrets, ensure-sops
- `validation` - check-yaml, check-json
- `custom` - managed-files-drift, apps-catalog-sync

**Example usage:**

```bash
lefthook run pre-commit --tags nix        # Only Nix linters
lefthook run pre-commit --tags security   # Only security checks
```

---

## Files to Modify

### 1. `flake.nix`

**Remove** git-hooks input (lines 22-28):

```nix
# DELETE:
git-hooks = {
  url = "github:cachix/git-hooks.nix";
  inputs = {
    flake-compat.follows = "dedupe_flake-compat";
    nixpkgs.follows = "nixpkgs";
  };
};
```

### 2. `modules/devshell.nix`

**CRITICAL:** The `inputsFrom = [ config.pre-commit.devShell ]` provided hook tool packages. Must add:

1. Direct tool binaries (for inline `run:` commands in lefthook.yml)
2. Nix-wrapped hook scripts (from `modules/meta/lefthook.nix`)

| Line    | Change                                                                       |
| ------- | ---------------------------------------------------------------------------- |
| 93      | Replace `pre-commit` with `lefthook`                                         |
| 93      | **Add direct tools:** `deadnix`, `statix`, `typos`, `ripsecrets`, `yamllint` |
| 93      | **Add Nix-wrapped scripts:** `config.packages.lefthook*`                     |
| 104     | **Remove** `inputsFrom = [ config.pre-commit.devShell ];`                    |
| 112-113 | Update help text for lefthook commands (see below)                           |
| 124     | Replace `${config.pre-commit.installationScript}` with `lefthook install`    |

**Help text changes (lines 112-113):**

```nix
# Change from:
echo "  pre-commit install     - Install git hooks"
echo "  pre-commit run         - Run hooks on staged files"

# To:
echo "  lefthook install       - Install git hooks"
echo "  lefthook run pre-commit - Run all pre-commit hooks"
```

**Updated packages list:**

```nix
packages =
  with pkgs;
  [
    nixfmt
    nil
    nix-tree
    nix-diff
    zsh
    act
    jq
    yq
    ripgrep
    lefthook                      # Replaces pre-commit

    # Direct tools for inline lefthook commands
    deadnix                       # For: deadnix --fail {staged_files}
    statix                        # For: lefthook-statix (also available directly)
    typos                         # For: typos --config .typos.toml {staged_files}
    ripsecrets                    # For: ripsecrets {staged_files}
    yamllint                      # For: yamllint -d relaxed {staged_files}
    # jq already present          # For: jq empty {staged_files}
    # sed from coreutils          # For: sed -i ... {staged_files}

    # Nix-wrapped hook scripts (from modules/meta/lefthook.nix)
    # These have explicit runtimeInputs and PATH isolation
    config.packages.lefthookTreefmt           # lefthook-treefmt
    config.packages.lefthookStatix            # lefthook-statix
    config.packages.lefthookEnsureSops        # lefthook-ensure-sops
    config.packages.lefthookManagedFilesDrift # lefthook-managed-files-drift
    config.packages.lefthookAppsCatalogSync   # lefthook-apps-catalog-sync

    age
    sops
    ssh-to-age
    ssh-to-pgp
    ghActionsRun
    ghActionsList
    config.packages.generation-manager
    config.treefmt.build.wrapper
  ];
```

**Note:** Nix-wrapped scripts include their own dependencies via `runtimeInputs`:

- `lefthook-treefmt`: treefmt, git, coreutils, util-linux (flock)
- `lefthook-statix`: statix, coreutils
- `lefthook-ensure-sops`: pre-commit-hook-ensure-sops
- `lefthook-managed-files-drift`: git, coreutils, diffutils, gnugrep, gnused, gawk
- `lefthook-apps-catalog-sync`: git, coreutils, gnugrep, gnused, gawk, findutils

### 3. `modules/system76/apps-enable.nix`

| Line | Change                                                      |
| ---- | ----------------------------------------------------------- |
| 137  | `lefthook.extended.enable = lib.mkOverride 1100 true;`      |
| 209  | `"pre-commit".extended.enable = lib.mkOverride 1100 false;` |

### 4. `build.sh`

Lines 354-355, change:

```bash
status_msg "${YELLOW}" "Running pre-commit hooks..."
nix develop --accept-flake-config "${NIX_FLAGS[@]}" -c pre-commit run --all-files
```

To:

```bash
status_msg "${YELLOW}" "Running lefthook pre-commit hooks..."
nix develop --accept-flake-config "${NIX_FLAGS[@]}" -c lefthook run pre-commit --all-files
```

### 5. `.gitignore` (via files module)

Add `/lefthook-local.yml` to Development section

---

## Files to Delete

1. `modules/meta/git-hooks.nix` - All functionality migrated to lefthook
2. `.pre-commit-config.yaml` - Symlink to nix store, will be orphaned

---

## Hook Migration Summary

| Hook                     | Strategy    | Tag        | Notes                                                  |
| ------------------------ | ----------- | ---------- | ------------------------------------------------------ |
| treefmt                  | Nix-wrapped | formatting | Caching/locking, `git diff HEAD`, skip merge/rebase    |
| trim-trailing-whitespace | **Removed** | -          | Covered by treefmt (prettier, shfmt handle whitespace) |
| deadnix                  | Inline      | nix        | `deadnix --fail {staged_files}`                        |
| statix                   | Nix-wrapped | nix        | File existence checks                                  |
| typos                    | Inline      | quality    | `typos --config .typos.toml {staged_files}`            |
| ripsecrets               | Inline      | security   | Covers API keys + private keys                         |
| ensure-sops              | Nix-wrapped | security   | Calls pre-commit-hook-ensure-sops                      |
| check-yaml               | Inline      | validation | `yamllint -d relaxed {staged_files}`                   |
| check-json               | Inline      | validation | `jq empty {staged_files}`                              |
| managed-files-drift      | Nix-wrapped | custom     | Auto-fix via `env` vars                                |
| apps-catalog-sync        | Nix-wrapped | custom     | Bidirectional sync                                     |

All hooks include `fail_text` with actionable guidance for fixing failures.

**Nix-Wrapped vs Inline:**

- **Nix-wrapped** (`lefthook-*`): Complex scripts with multiple dependencies, defined in `modules/meta/lefthook.nix` with explicit `runtimeInputs`
- **Inline** (`run: tool ...`): Simple tool invocations, tools provided directly in devshell packages

**Removed hooks:**

- `detect-private-keys` - ripsecrets covers 8/10 patterns (missing only `BEGIN ENCRYPTED PRIVATE KEY` and `BEGIN OpenVPN Static key V1` which are edge cases)
- `trim-trailing-whitespace` - treefmt's formatters (prettier, shfmt, nixfmt) already handle trailing whitespace for all formatted file types

**Key Improvements from Review:**

- **Idiomatic Nix**: Hook scripts are Nix derivations with explicit dependencies and PATH isolation
- Groups with inherited `exclude` - DRY pattern, each group defines excludes once
- `output: [meta, summary, failure, success]` - Cleaner output with success visibility
- `fail_on_changes: ci` - Ensures CI fails if hooks modify uncommitted files
- `skip: [merge, rebase]` at hook level - All hooks skip during merge/rebase (skip is NOT inherited by groups)
- `priority` on groups - Fast checks (validation, security) run first for fail-fast behavior
- `--` separator - Safe handling of filenames starting with `-`

---

## Implementation Order

1. **Create new Nix module** (no breaking changes)
   - Create `modules/meta/lefthook.nix` with all Nix-wrapped hook scripts
   - Create `lefthook.yml` in repo root
   - Verify flake evaluates: `nix flake check --no-build`

2. **Update devshell** (parallel testing possible)
   - Add `lefthook` and direct tool packages
   - Add `config.packages.lefthook*` Nix-wrapped scripts
   - Keep `pre-commit` temporarily for comparison testing
   - Verify scripts are available: `which lefthook-treefmt lefthook-statix ...`

3. **Test migration**
   - Run `lefthook run pre-commit --all-files`
   - Compare results with `pre-commit run --all-files`
   - Test each tag: `--tags nix`, `--tags security`, etc.
   - Verify Nix-wrapped scripts have isolated PATH: `lefthook-treefmt` should work even outside devshell (self-contained)

4. **Cutover**
   - Remove `inputsFrom` and `installationScript` from devshell
   - Update build.sh to use lefthook
   - Update apps-enable.nix (enable lefthook, disable pre-commit)

5. **Cleanup**
   - Remove git-hooks input from flake.nix
   - Delete modules/meta/git-hooks.nix
   - Update .gitignore (add `/lefthook-local.yml`)
   - Remove orphaned .pre-commit-config.yaml symlink
   - remove `".pre-commit-config.yaml"` from modules/development/treefmt.nix

---

## Verification Steps

```bash
# 1. Verify flake evaluates with new module
nix flake check --no-build

# 2. Enter dev shell and verify lefthook + tools
nix develop
lefthook --version

# 3. Verify direct tools are available (for inline commands)
which deadnix statix typos ripsecrets yamllint jq

# 4. Verify Nix-wrapped scripts are available
which lefthook-treefmt lefthook-statix lefthook-ensure-sops \
      lefthook-managed-files-drift lefthook-apps-catalog-sync

# 5. Verify Nix-wrapped scripts are self-contained (have isolated PATH)
# This should work even outside devshell because runtimeInputs are bundled
nix build .#lefthookTreefmt && echo "Build successful - script is self-contained"

# 6. Install hooks
lefthook install
cat .git/hooks/pre-commit  # Should reference lefthook

# 7. Run all hooks
lefthook run pre-commit --all-files

# 8. Test by tag
lefthook run pre-commit --tags nix --all-files
lefthook run pre-commit --tags security --all-files
lefthook run pre-commit --tags formatting --all-files

# 9. Test actual commit
echo "# test" >> README.md
git add README.md
git commit -m "test: verify lefthook"  # Hooks should trigger
git reset --soft HEAD~1  # Undo test commit

# 10. Verify build.sh integration
./build.sh --skip-check
```

**Rollback procedure** (if migration fails):

```bash
# Restore old hooks
git checkout .git/hooks/
nix develop -c pre-commit install

# Revert config changes
git checkout modules/devshell.nix build.sh
```

---

## Critical Files Reference

| File                               | Action     | Notes                                              |
| ---------------------------------- | ---------- | -------------------------------------------------- |
| `modules/meta/lefthook.nix`        | **CREATE** | New module with Nix-wrapped hook scripts           |
| `lefthook.yml`                     | **CREATE** | Static hook configuration (repo root)              |
| `modules/meta/git-hooks.nix`       | DELETE     | Replaced by lefthook.nix                           |
| `modules/devshell.nix`             | MODIFY     | Add lefthook + packages + Nix-wrapped scripts      |
| `modules/system76/apps-enable.nix` | MODIFY     | Lines 137 (lefthook=true), 209 (pre-commit=false)  |
| `build.sh`                         | MODIFY     | Lines 354-355 (use lefthook instead of pre-commit) |
| `flake.nix`                        | MODIFY     | Remove git-hooks input (lines 22-28)               |
| `.pre-commit-config.yaml`          | DELETE     | Orphaned symlink to /nix/store                     |
