# Chromium Web Apps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the firefoxpwa subsystem with a declarative Chromium web-app module on brave-origin that gives every app its own isolated profile, per-origin permissions, opt-in tray backgrounding, and opt-in session keep-alive.

**Architecture:** A NixOS-scope module owns the managed enterprise policy (permissions and extensions) written into `/etc/brave/policies/managed/`; a Home Manager module owns per-app launchers, `--user-data-dir` isolation, desktop entries, and kdocker tray wrapping. App definitions live in one typed keyed attrset that both scopes read. No installer script, no systemd unit, no runtime state reconciliation.

**Tech Stack:** Nix (flake-parts, Dendritic pattern), Home Manager, sops-nix, brave-origin (Chromium 1.93.x), Chromium enterprise policy, MV3 extensions, kdocker.

______________________________________________________________________

## Decisions Recorded

Locked before writing this plan. Do not relitigate during execution.

| Decision     | Choice                                           | Rationale                                                                                                                                                                |
| ------------ | ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Base browser | `brave-origin`                                   | Verified reads `/etc/brave/policies` (binary strings); honors `--load-extension` because it is not a `GOOGLE_CHROME_BRANDING` build; already enabled on both hosts.      |
| Isolation    | per-app `--user-data-dir`                        | Complete cookie/storage/extension separation. Required because `--load-extension` is per browser instance, not per profile.                                              |
| Extensions   | Hybrid                                           | Third-party from the Web Store via `ExtensionSettings` (correct IDs, 1Password native messaging works); only the generated keep-alive extension uses `--load-extension`. |
| Tray         | kdocker per app                                  | `-i` per-app icon, `-z` keep-running, `-l` iconify on focus loss. Opt-in per app.                                                                                        |
| Keep-alive   | Generated MV3 extension, reload only when hidden | `chrome.alarms` wakes the service worker; skips the reload when the app window is focused.                                                                               |
| Secret URLs  | One sops-rendered policy file                    | Avoids Chromium's config-dir merge, where a repeated list policy has one file win outright instead of concatenating.                                                     |
| PR #435      | Close, salvage the two unrelated fixes           | The compgen and statix fixes are repo-wide and must survive.                                                                                                             |
| Catalog      | DMail + full M365 including Teams                | Teams was excluded from #435 only because it rejects Gecko.                                                                                                              |
| Policy scope | Full hardened set plus webapp entries            | Lifted from `modules/browsers/brave/apps.nix` and shared.                                                                                                                |
| Option shape | Keyed attrset with submodule                     | Per-key override without rewriting the catalog.                                                                                                                          |
| PR structure | Three PRs                                        | Salvage, remove, implement.                                                                                                                                              |
| Tests        | Eval checks plus generated-artifact fixtures     | No installer shell exists in this design.                                                                                                                                |

### Verified facts this plan depends on

- `brave-origin` binary contains the string `/etc/brave/policies`. Reproduce: `strings -a "$(nix eval --impure --raw --expr 'with import <nixpkgs> {}; "${brave-origin}"')/opt/brave.com/brave-origin/brave" | rg '^/etc/brave'`
- `--load-extension` is refused only under `BUILDFLAG(GOOGLE_CHROME_BRANDING)` and under Enhanced Safe Browsing. The hardened policy set pins `SafeBrowsingProtectionLevel = 1` (standard), so it stays available.
- Policy names and types confirmed against the Chromium policy registry: `AudioCaptureAllowed` (bool), `VideoCaptureAllowed` (bool), `ScreenCaptureAllowed` (bool), `DefaultNotificationsSetting` (int), `DefaultClipboardSetting` (int), `DefaultSensorsSetting` (int), `DefaultWindowManagementSetting` (int), `DefaultLocalFontsSetting` (int), `ExtensionSettings` (dict), `BackgroundModeEnabled` (bool).
- Allowlist policies that exist: `AudioCaptureAllowedUrls`, `VideoCaptureAllowedUrls`, `NotificationsAllowedForUrls`, `ClipboardAllowedForUrls`, `ScreenCaptureAllowedByOrigins`, `SensorsAllowedForUrls`, `WindowManagementAllowedForUrls`, `LocalFontsAllowedForUrls`.
- **Geolocation has no allowlist policy.** Only `GeolocationBlockedForUrls` and `PreciseGeolocationAllowedForUrls` exist. Geolocation is therefore block-only in this design and is deliberately absent from the permission submodule.
- `kdocker` 6.2 flags used: `-i <file>` custom icon, `-z` keep running with no windows, `-q` quiet, `-l` iconify on focus lost, `-d <sec>` command start timeout.

______________________________________________________________________

## File Structure

### PR 1: salvage (files modified)

- `tests/prune-old-stashes/run.sh`: replace `compgen` guard with `declare -F`
- `modules/meta/build-time-shell.nix`: new flake check banning `compgen` at a command position in build-time shell
- `modules/meta/hooks/statix.nix`: whole-tree branch when invoked with no arguments

### PR 2: removal (files deleted)

- `modules/browsers/firefoxpwa/` (entire directory)
- `packages/firefoxpwa-dmail-install/`
- `modules/custom-overlays/firefoxpwa.nix`
- `modules/browsers/_firefoxpwa-extension-pin.json`
- `scripts/update-firefoxpwa-extension.py`
- `.github/workflows/update-firefoxpwa-extension.yml`

### PR 2: removal (files modified)

- `modules/browsers/_gecko-extension-data.nix`: drop `firefoxpwaExt`, the pin reader, `tabReloader`, `firefoxpwaRuntimePolicies`, and their `inherit` entries
- `modules/browsers/_gecko-extensions.nix`: drop the `firefoxpwaEnabled`/`firefoxpwaPackage` arguments and the gated extension entry
- `modules/browsers/_gecko-mk-profile.nix`: drop the two pass-through arguments
- `modules/browsers/firefox/home.nix`: drop the osConfig lookups and the native-messaging host
- `modules/browsers/librewolf/home.nix`: same
- `modules/hosts/common/home-manager-apps.nix:84`: drop `"firefoxpwa"`
- `modules/hosts/common/apps-enable.nix:155`: drop the catalog entry
- `modules/tpnix/apps-enable.nix:79-84`: drop the `dmail.enable` override block
- `modules/meta/cache-roots.nix:52`: drop `"firefoxpwa"`
- `.github/workflows/update-flake.yml:88-92`: drop the pin sync step
- `pyproject.toml`: drop the script references
- `docs/architecture/04-home-manager.md:94`, `docs/reference/binary-cache-coverage.md:73,159`

### PR 3: implementation (files created)

| File                                                  | Responsibility                                                                 |
| ----------------------------------------------------- | ------------------------------------------------------------------------------ |
| `modules/browsers/_chromium-hardening.nix`            | The hardened policy set, shared by brave and brave-origin. Pure data.          |
| `modules/browsers/webapps/_catalog.nix`               | Default app catalog. Pure data, no `lib`.                                      |
| `modules/browsers/webapps/_policy.nix`                | Pure function: apps attrset to Chromium policy attrset.                        |
| `modules/browsers/webapps/_reload-extension.nix`      | Pure function: builds the per-app MV3 keep-alive extension derivation.         |
| `modules/browsers/webapps/apps.nix`                   | NixOS module: options, sops policy template, `environment.etc`.                |
| `modules/browsers/webapps/home.nix`                   | Home Manager module: launchers, data dirs, desktop entries, tray.              |
| `modules/browsers/webapps/enable.nix`                 | hosts-common baseline toggle.                                                  |
| `modules/browsers/webapps/policy-check.nix`           | Flake check: generated policy vs fixture, plus the disjoint-key invariant.     |
| `modules/browsers/webapps/module-check.nix`           | Flake check: Home Manager module evaluates and produces the expected launcher. |
| `modules/browsers/webapps/check-fixtures/policy.json` | Expected policy output.                                                        |
| `modules/browsers/webapps/check-fixtures/gecko.yaml`  | Non-secret fixture for the HM eval check.                                      |

### PR 3: implementation (files modified)

- `modules/browsers/brave/apps.nix`: import the shared hardened set instead of defining it inline
- `modules/browsers/brave-origin/apps.nix`: gain `enableManagedPolicies` / `managedPolicies`, write `/etc/brave/policies/managed/extended.json`
- `modules/hosts/common/home-manager-apps.nix`: add `"webapps"` to `sharedBrowserNames`
- `modules/meta/cache-roots.nix`: add `"brave-origin"`
- `docs/architecture/04-home-manager.md`, `docs/reference/local-mirrors.md` is untouched; `README.md` is regenerated

______________________________________________________________________

# Part 1: Salvage from PR #435

The branch is at `/home/vx/trees/nixos/feat-firefoxpwa-m365`. Its commits 2 and 3 fix repo-wide defects that have nothing to do with firefoxpwa. They must land before the removal so main stops carrying a check that reports a pass while verifying nothing.

### Task 1: Rescue the compgen and statix fixes onto a clean branch

**Files:**

- Modify: `tests/prune-old-stashes/run.sh`

- Create: `modules/meta/build-time-shell.nix`

- Modify: `modules/meta/hooks/statix.nix`

- [ ] **Step 1: Create the worktree**

```bash
cd /home/vx/nixos
git worktree add "$HOME/trees/nixos/fix-build-time-shell" -b "fix/build-time-shell"
```

- [ ] **Step 2: Identify the two commits to cherry-pick**

```bash
cd /home/vx/trees/nixos/feat-firefoxpwa-m365
git log --oneline --format='%h %s' main..HEAD -- \
  tests/prune-old-stashes/run.sh modules/meta/build-time-shell.nix modules/meta/hooks/statix.nix
```

Expected: commit hashes touching only those three paths. Record them as `$COMPGEN_SHA` and `$STATIX_SHA`.

- [ ] **Step 3: Cherry-pick them onto the clean branch**

```bash
cd "$HOME/trees/nixos/fix-build-time-shell"
git cherry-pick "$COMPGEN_SHA" "$STATIX_SHA"
```

If a hunk conflicts because it also touched `modules/browsers/firefoxpwa/m365-check.nix`, drop that path: it is deleted in PR 2.

```bash
git rm --cached modules/browsers/firefoxpwa/m365-check.nix 2>/dev/null || true
git checkout --ours . 2>/dev/null || true
```

- [ ] **Step 4: Verify the compgen fix actually detects what it claims**

```bash
cd "$HOME/trees/nixos/fix-build-time-shell"
rg -n 'declare -F' tests/prune-old-stashes/run.sh
rg -n 'compgen' tests/ modules/ packages/
```

Expected: `declare -F` present in the test runner; no `compgen` at a command position anywhere.

- [ ] **Step 5: Run the checks**

```bash
cd "$HOME/trees/nixos/fix-build-time-shell"
nix fmt
nix flake check path:. --accept-flake-config --no-build --offline
```

Expected: exit 0.

- [ ] **Step 6: Commit and open the PR**

```bash
cd "$HOME/trees/nixos/fix-build-time-shell"
git add tests/prune-old-stashes/run.sh modules/meta/build-time-shell.nix modules/meta/hooks/statix.nix
git commit -m "fix(checks): stop trusting compgen in build-time shell text

The bash a runCommand builder runs is built without programmable completion, so \`compgen -G\` resolves to no command
and a condition context turns that into false rather than an error. Every leftover-temporary assertion written with it
reported a pass while checking nothing. tests/prune-old-stashes/run.sh used the same builtin for its
defined-but-never-ran guard and passes today only because modules/meta/script-tests.nix puts pkgs.bash on PATH.
Replaced with \`declare -F\`, and checks.build-time-shell now scans modules/, packages/ and tests/ for the builtin at a
command position. statix reached only staged files, so checks.statix-tree runs hook-statix with no arguments.

Validation: nix fmt; nix flake check path:. --accept-flake-config --no-build --offline"
git push -u origin fix/build-time-shell
gh pr create --title "fix(checks): stop trusting compgen in build-time shell text" --body "$(cat <<'EOF'
## Summary

- `compgen -G` is unavailable in `runCommand` bash, so every leftover-temporary assertion using it passed without
  checking anything. Replaced with `declare -F`.
- `checks.build-time-shell` scans `modules/`, `packages/` and `tests/` for the builtin at a command position.
- `checks.statix-tree` runs `hook-statix` with no arguments so lints in unstaged files are reachable in CI.

Rescued from #435, which is being closed unmerged.

## Test plan

- `nix flake check path:. --accept-flake-config --no-build --offline`
- Planted-lint proof: the statix check reports a planted lint before scanning the tree.
EOF
)"
```

- [ ] **Step 7: Close PR #435 with a pointer**

```bash
gh pr close 435 --comment "Closing unmerged. The firefoxpwa subsystem is being replaced by a Chromium web-app module (see docs/drafts/chromium-webapps-plan.md); the M365 catalog carries over as data. The two unrelated fixes from this branch (compgen false-pass, whole-tree statix) are rescued in the PR linked above."
```

______________________________________________________________________

# Part 2: Remove firefoxpwa

Do not start until PR 1 has merged. Every step here is a deletion or an unwiring; no behavior is added.

### Task 2: Delete the firefoxpwa-owned files

**Files:**

- Delete: `modules/browsers/firefoxpwa/`, `packages/firefoxpwa-dmail-install/`, `modules/custom-overlays/firefoxpwa.nix`, `modules/browsers/_firefoxpwa-extension-pin.json`, `scripts/update-firefoxpwa-extension.py`, `.github/workflows/update-firefoxpwa-extension.yml`

- [ ] **Step 1: Create the worktree**

```bash
cd /home/vx/nixos
git worktree add "$HOME/trees/nixos/refactor-drop-firefoxpwa" -b "refactor/drop-firefoxpwa"
cd "$HOME/trees/nixos/refactor-drop-firefoxpwa"
```

- [ ] **Step 2: Record the pre-removal reference set**

```bash
rg -n -i 'firefoxpwa|PWAsForFirefox' --hidden -g '!.git' -g '!docs/nixos-manual' > /tmp/firefoxpwa-before.txt
wc -l /tmp/firefoxpwa-before.txt
```

Expected: 61 matching lines across 20 files. This is the checklist; the file is consulted again in Task 6.

- [ ] **Step 3: Remove the files using the recoverable deletion path**

```bash
rip modules/browsers/firefoxpwa \
    packages/firefoxpwa-dmail-install \
    modules/custom-overlays/firefoxpwa.nix \
    modules/browsers/_firefoxpwa-extension-pin.json \
    scripts/update-firefoxpwa-extension.py \
    .github/workflows/update-firefoxpwa-extension.yml
```

- [ ] **Step 4: Verify only the intended paths are gone**

```bash
git status --short
```

Expected: only `D ` entries for the six paths above, nothing else.

- [ ] **Step 5: Commit**

```bash
git add -A modules/browsers/firefoxpwa packages/firefoxpwa-dmail-install \
  modules/custom-overlays/firefoxpwa.nix modules/browsers/_firefoxpwa-extension-pin.json \
  scripts/update-firefoxpwa-extension.py .github/workflows/update-firefoxpwa-extension.yml
git commit -m "refactor(firefoxpwa)!: delete the firefoxpwa module tree

PWAsForFirefox installs every site into one shared profile unless a profile is created per site, so the isolation the
module was carrying its complexity for was never actually configured: packages/firefoxpwa-dmail-install called
\`firefoxpwa site install\` with no --profile. Adding it means tracking a second ulid in a script that already needed
21 KB of shell and a 47 KB regression check for one site. Replaced by a Chromium web-app module.

Unwiring of the gecko browsers, the app catalog and the workflows follows in the next commits."
```

### Task 3: Unwire firefoxpwa from the gecko browser stack

**Files:**

- Modify: `modules/browsers/_gecko-extension-data.nix:45-67,69-73,98-126,146-150`

- Modify: `modules/browsers/_gecko-extensions.nix:10-14,35-36,363-372`

- Modify: `modules/browsers/_gecko-mk-profile.nix:17-18,31-32`

- Modify: `modules/browsers/firefox/home.nix:14-20,26-27,67-68,73`

- Modify: `modules/browsers/librewolf/home.nix:33-39,45-46,86,91`

- [ ] **Step 1: Strip `_gecko-extension-data.nix`**

Delete these bindings and their comments: `firefoxpwaExt` (the `firefoxpwa@filips.si` identifier), `firefoxpwaExtensionPin` (the `builtins.fromJSON (builtins.readFile ./_firefoxpwa-extension-pin.json)` reader), `mkFirefoxpwaInstallUrl` (including its stale-pin `throw`), `tabReloader` (PWA-runtime only, per its own comment), and the whole `firefoxpwaRuntimePolicies` attrset. Remove `firefoxpwaExt`, `mkFirefoxpwaInstallUrl` and `firefoxpwaRuntimePolicies` from the trailing `inherit` list.

Keep `mkNormalInstalledPolicy`: it is still referenced by the regular browsers.

Verify `tabReloader` has no other consumer before deleting:

```bash
rg -n 'tabReloader' modules/
```

Expected: matches only inside `_gecko-extension-data.nix`.

- [ ] **Step 2: Strip `_gecko-extensions.nix`**

Remove the `firefoxpwaEnabled ? false,` and `firefoxpwaPackage ? null,` function arguments and their leading comment, remove `firefoxpwaExt` and `mkFirefoxpwaInstallUrl` from the `inherit` of `_gecko-extension-data.nix`, and delete the whole trailing:

```nix
// lib.optionalAttrs firefoxpwaEnabled {
  "${firefoxpwaExt}" = { ... };
}
```

- [ ] **Step 3: Strip `_gecko-mk-profile.nix`**

Remove the `firefoxpwaEnabled ? false,` and `firefoxpwaPackage ? pkgs.firefoxpwa,` arguments and the matching `inherit` entries in the `geckoExtensions = import ./_gecko-extensions.nix { ... }` call.

- [ ] **Step 4: Strip `firefox/home.nix` and `librewolf/home.nix`**

In each, delete the `firefoxpwaEnabled` / `firefoxpwaPackage` `lib.attrByPath` lookups, their `inherit` entries in the `mkProfile` argument set, and the `++ lib.optional firefoxpwaEnabled firefoxpwaPackage` on the native-messaging-hosts list together with its comment. The list must keep every other element unchanged.

- [ ] **Step 5: Verify the gecko stack still evaluates**

```bash
nix fmt
nix flake check path:. --accept-flake-config --no-build --offline
```

Expected: exit 0. A leftover reference surfaces here as an undefined-variable error.

- [ ] **Step 6: Commit**

```bash
git add modules/browsers/_gecko-extension-data.nix modules/browsers/_gecko-extensions.nix \
  modules/browsers/_gecko-mk-profile.nix modules/browsers/firefox/home.nix modules/browsers/librewolf/home.nix
git commit -m "refactor(browsers)!: drop firefoxpwa wiring from the gecko stack

Removes the PWAsForFirefox management extension entry, the AMO pin reader and its stale-pin throw, the Tab Reloader
add-on (installed only into PWA runtime profiles, never the regular browsers), and the firefoxpwaRuntimePolicies set
the deleted overlay injected. firefox and librewolf lose the firefoxpwa native-messaging host.

Validation: nix flake check path:. --accept-flake-config --no-build --offline"
```

### Task 4: Unwire firefoxpwa from host configuration and CI

**Files:**

- Modify: `modules/hosts/common/home-manager-apps.nix:84`

- Modify: `modules/hosts/common/apps-enable.nix:155`

- Modify: `modules/tpnix/apps-enable.nix:79-84`

- Modify: `modules/meta/cache-roots.nix:52`

- Modify: `.github/workflows/update-flake.yml:88-92`

- Modify: `pyproject.toml:13-14,36`

- [ ] **Step 1: Remove the shared browser registration**

In `modules/hosts/common/home-manager-apps.nix`, delete the `"firefoxpwa"` element from `sharedBrowserNames` so the list reads:

```nix
  sharedBrowserNames = [
    "firefox"
    "google-chrome"
    "librewolf"
    "ungoogled-chromium"
  ];
```

- [ ] **Step 2: Remove the catalog entry**

In `modules/hosts/common/apps-enable.nix`, delete the line:

```nix
      firefoxpwa.extended.enable = lib.mkOverride 1100 true;
```

- [ ] **Step 3: Remove the per-host override**

In `modules/tpnix/apps-enable.nix`, the `configurations.nixos.tpnix.module` block collapses back to a plain `mapAttrs` because `firefoxpwa.dmail.enable` was its only non-flat entry:

```nix
  configurations.nixos.tpnix.module = {
    programs = lib.mapAttrs mkExtendedEnable programOverrides;
    services = lib.mapAttrs mkExtendedEnable serviceOverrides;
  };
```

Delete the three-line comment above it that explains the non-flat routing, and drop `lib.recursiveUpdate` if `lib` is now otherwise unused in that expression (it is not; `lib.mapAttrs` remains).

- [ ] **Step 4: Remove the cache root**

In `modules/meta/cache-roots.nix`, delete `"firefoxpwa"` from `hostPackageNames`.

- [ ] **Step 5: Remove the workflow step**

In `.github/workflows/update-flake.yml`, delete the whole `- name: Sync firefoxpwa extension pin` step including its `if:`, comment and `run:` lines.

- [ ] **Step 6: Remove the Python tooling references**

In `pyproject.toml`, delete the `update-firefoxpwa-extension.py` mention from the header comment and the `"scripts/update-firefoxpwa-extension.py" = "py312"` entry.

- [ ] **Step 7: Verify nothing references the deleted paths**

```bash
rg -n -i 'firefoxpwa|PWAsForFirefox' --hidden -g '!.git' -g '!docs/nixos-manual'
```

Expected: only `docs/architecture/04-home-manager.md` and `docs/reference/binary-cache-coverage.md`, handled in Task 5.

- [ ] **Step 8: Validate and commit**

```bash
nix fmt
nix flake check path:. --accept-flake-config --no-build --offline
git add modules/hosts/common/home-manager-apps.nix modules/hosts/common/apps-enable.nix \
  modules/tpnix/apps-enable.nix modules/meta/cache-roots.nix .github/workflows/update-flake.yml pyproject.toml
git commit -m "refactor(hosts)!: drop firefoxpwa from the app catalog and CI

Removes the shared browser registration, the common baseline and tpnix dmail override, the cache root that existed
only because the deleted overlay forced a firefoxpwa-unwrapped rebuild, the update-flake pin sync step and the ruff
target for the deleted script.

Validation: nix flake check path:. --accept-flake-config --no-build --offline"
```

### Task 5: Update documentation and regenerate managed artifacts

**Files:**

- Modify: `docs/architecture/04-home-manager.md:94`

- Modify: `docs/reference/binary-cache-coverage.md:73,159`

- Regenerate: `README.md`

- [ ] **Step 1: Rewrite the browser-modules paragraph**

In `docs/architecture/04-home-manager.md`, the sentence beginning "A sibling file can extend the same `browsers.<name>` key" cites firefoxpwa as its worked example. Replace the firefoxpwa clause so the paragraph ends:

```markdown
A sibling file can extend the same `browsers.<name>` key, merged the same way `apps.stylix-gui` is above: `modules/browsers/webapps/home.nix` owns the per-app launchers and data directories, and `modules/browsers/webapps/apps.nix` owns the NixOS-scope managed policy that the same app catalog drives.
```

- [ ] **Step 2: Update the cache coverage reference**

In `docs/reference/binary-cache-coverage.md`, change the parenthetical on line 73 from `(firefoxpwa policy injection, john patches)` to `(john patches)`, and delete the `| firefoxpwa | system76, tpnix |` table row.

- [ ] **Step 3: Regenerate managed artifacts**

```bash
nix develop path:. --accept-flake-config -c write-files --offline
git diff --stat
```

Expected: a `README.md` diff only if firefoxpwa appeared in generated output. Review it before staging.

- [ ] **Step 4: Confirm the reference set is empty**

```bash
rg -n -i 'firefoxpwa|PWAsForFirefox' --hidden -g '!.git' -g '!docs/nixos-manual'
```

Expected: no output.

- [ ] **Step 5: Validate the host closure still builds**

```bash
nix flake check path:. --accept-flake-config --no-build --offline
nix build "path:.#nixosConfigurations.tpnix.config.system.build.toplevel" --no-link
```

Expected: both succeed.

- [ ] **Step 6: Commit and open the PR**

```bash
git add docs/architecture/04-home-manager.md docs/reference/binary-cache-coverage.md README.md
git commit -m "docs(browsers): retire the firefoxpwa references

Validation: nix flake check path:. --accept-flake-config --no-build --offline;
nix build path:.#nixosConfigurations.tpnix.config.system.build.toplevel"
git push -u origin refactor/drop-firefoxpwa
gh pr create --title "refactor(browsers)!: remove the firefoxpwa subsystem" --body "$(cat <<'EOF'
## Summary

Removes PWAsForFirefox entirely: the module tree, the DMail installer derivation, the runtime policy overlay, the AMO
extension pin and its weekly workflow, the cache root, and the gecko-side wiring.

The isolation the subsystem's complexity paid for was never configured. `packages/firefoxpwa-dmail-install` called
`firefoxpwa site install` with no `--profile`, and PWAsForFirefox installs into the shared default profile when none is
given, so DMail shared a cookie jar with every extension-installed site.

Replaced in the following PR by a Chromium web-app module on brave-origin. Plan:
`docs/drafts/chromium-webapps-plan.md`.

## Test plan

- `nix flake check path:. --accept-flake-config --no-build --offline`
- `nix build path:.#nixosConfigurations.tpnix.config.system.build.toplevel`
- `rg -i 'firefoxpwa|PWAsForFirefox'` returns nothing outside `docs/nixos-manual/`
EOF
)"
```

### Task 6: Clean up user-side leftovers after the switch

Not part of the PR. Run once on each host after `refactor/drop-firefoxpwa` merges and the switch completes. The old userdata tree holds real PWA profile state and is not deleted by the module removal.

- [ ] **Step 1: Confirm what remains**

```bash
ls -la "${XDG_DATA_HOME:-$HOME/.local/share}/firefoxpwa"
ls "${XDG_DATA_HOME:-$HOME/.local/share}/applications" | rg -i 'FFPWA|firefoxpwa'
```

- [ ] **Step 2: Remove the launcher entries and the userdata tree**

```bash
rip "${XDG_DATA_HOME:-$HOME/.local/share}"/applications/FFPWA-*.desktop
rip "${XDG_DATA_HOME:-$HOME/.local/share}/firefoxpwa"
systemctl --user reset-failed firefoxpwa-dmail.service 2>/dev/null || true
```

Both paths stay recoverable through the `rip` graveyard.

______________________________________________________________________

# Part 3: Implement the Chromium web-app module

Do not start until PR 2 has merged.

### Task 7: Extract the shared Chromium hardening set

**Files:**

- Create: `modules/browsers/_chromium-hardening.nix`

- Modify: `modules/browsers/brave/apps.nix:39-163`

- [ ] **Step 1: Create the worktree**

```bash
cd /home/vx/nixos
git worktree add "$HOME/trees/nixos/feat-chromium-webapps" -b "feat/chromium-webapps"
cd "$HOME/trees/nixos/feat-chromium-webapps"
```

- [ ] **Step 2: Create the shared hardening file**

The attrset to move is `modules/browsers/brave/apps.nix` lines 40-161: line 39 is `defaultManagedPolicies = {`, line 162 is the closing `}`, and line 163 is the `// managedDefaultSearchProvider;` merge that callers keep. Extract it mechanically so nothing is transcribed by hand:

```bash
cd "$HOME/trees/nixos/feat-chromium-webapps"

{
  cat <<'HEADER'
/*
  Internal: shared hardened managed-policy set for Brave-family browsers
  Description: Privacy, telemetry, permission and Brave-feature policy applied
  to every Brave build this repo installs. Written to /etc/brave/policies/managed
  by modules/browsers/brave/apps.nix and modules/browsers/brave-origin/apps.nix.
  The leading underscore keeps this file out of module auto-discovery.

  Notes:
    * Brave policy keys were checked against Brave policy_templates.zip VERSION 147.1.91.88.
    * Per-origin allowlists are NOT here. modules/browsers/webapps/_policy.nix owns
      those and writes a separate file; the key sets must stay disjoint because
      Chromium's config-dir loader lets one file win a repeated key outright
      rather than merging it. modules/browsers/webapps/policy-check.nix asserts that.
*/
{
  policies = {
HEADER
  sed -n '40,161p' modules/browsers/brave/apps.nix
  printf '  };\n}\n'
} > modules/browsers/_chromium-hardening.nix

nix fmt modules/browsers/_chromium-hardening.nix
```

Confirm the boundaries were right before continuing:

```bash
head -20 modules/browsers/_chromium-hardening.nix | tail -3
rg -c '=' modules/browsers/_chromium-hardening.nix
rg -n 'managedDefaultSearchProvider|defaultManagedPolicies' modules/browsers/_chromium-hardening.nix || echo "merge line correctly excluded"
```

Expected: the first policy line is `BraveAIChatEnabled = false;`, roughly 80 assignments, and `merge line correctly excluded`.

- [ ] **Step 3: Point brave at the shared file**

In `modules/browsers/brave/apps.nix`, replace the inline `defaultManagedPolicies = { ... };` with:

```nix
      defaultManagedPolicies = (import ../_chromium-hardening.nix).policies // managedDefaultSearchProvider;
```

Keep the `inherit (import ../_chromium-policies.nix) managedDefaultSearchProvider;` line above it unchanged.

- [ ] **Step 4: Prove the move changed nothing**

```bash
nix fmt
nix eval --json "path:.#nixosConfigurations.tpnix.config.programs.brave.extended.managedPolicies" \
  --accept-flake-config 2>/dev/null | jq -S . > /tmp/brave-policies-after.json
git stash
nix eval --json "path:.#nixosConfigurations.tpnix.config.programs.brave.extended.managedPolicies" \
  --accept-flake-config 2>/dev/null | jq -S . > /tmp/brave-policies-before.json
git stash apply
diff /tmp/brave-policies-before.json /tmp/brave-policies-after.json
```

Expected: `diff` produces no output.

- [ ] **Step 5: Commit**

```bash
git add modules/browsers/_chromium-hardening.nix modules/browsers/brave/apps.nix
git commit -m "refactor(browsers): share the Brave hardening policy set

brave-origin needs the same ~80 policies and reads the same /etc/brave/policies directory (confirmed in the binary's
own string table), so the set moves out of brave/apps.nix into _chromium-hardening.nix rather than being duplicated.
Byte-identical output proven by diffing the evaluated managedPolicies before and after.

Validation: nix eval of programs.brave.extended.managedPolicies, diffed against the pre-refactor value"
```

### Task 8: Give brave-origin a managed policy surface

**Files:**

- Modify: `modules/browsers/brave-origin/apps.nix`

- [ ] **Step 1: Add the policy options and the etc entry**

Replace the option block and `config` in `modules/browsers/brave-origin/apps.nix` with:

```nix
      options.programs."brave-origin".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable brave-origin.";
        };

        package = lib.mkPackageOption pkgs "brave-origin" { };

        enableManagedPolicies = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to install the shared Brave managed policies for brave-origin.";
        };

        managedPolicies = lib.mkOption {
          type = lib.types.attrs;
          default = (import ../_chromium-hardening.nix).policies // managedDefaultSearchProvider;
          defaultText = lib.literalExpression "(import ../_chromium-hardening.nix).policies // managedDefaultSearchProvider";
          description = ''
            Brave enterprise policies written to /etc/brave/policies/managed/extended.json.
            Per-origin allowlists are not written here; modules/browsers/webapps owns
            those in a separate file with a disjoint key set.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        environment = {
          systemPackages = [ cfg.package ];

          etc = lib.mkIf cfg.enableManagedPolicies {
            "brave/policies/managed/extended.json".text = builtins.toJSON cfg.managedPolicies;
          };
        };
      };
```

Add above the option block, inside the existing `let`:

```nix
      inherit (import ../_chromium-policies.nix) managedDefaultSearchProvider;
```

- [ ] **Step 2: Update the module header**

In the header comment, change the Summary bullet `* Exposes the upstream binary as \`brave-origin\` without managed enterprise policies.\` to:

```
    * Exposes the upstream binary as `brave-origin` with the shared Brave managed policy set.
```

and add to Options:

```
    /etc/brave/policies/managed/extended.json: Managed policy file generated by this module.
```

- [ ] **Step 3: Guard against brave and brave-origin fighting over one file**

Both modules write `/etc/brave/policies/managed/extended.json`. Add to `modules/browsers/brave-origin/apps.nix`, inside `config`:

```nix
        assertions = [
          {
            assertion = !(config.programs.brave.extended.enable && cfg.enableManagedPolicies);
            message = ''
              programs.brave.extended.enable and programs.brave-origin.extended.enableManagedPolicies both write
              /etc/brave/policies/managed/extended.json. Brave and Brave Origin share one policy directory
              (verified in the brave-origin binary's string table), so only one may own that file. Disable
              programs.brave-origin.extended.enableManagedPolicies, or disable programs.brave.extended.enable.
            '';
          }
        ];
```

- [ ] **Step 4: Verify the policy file lands**

```bash
nix fmt
nix eval --raw "path:.#nixosConfigurations.tpnix.config.environment.etc.\"brave/policies/managed/extended.json\".text" \
  --accept-flake-config | jq -r 'keys | length'
```

Expected: a count of roughly 80. If the command errors with a missing attribute, `brave-origin.extended.enable` is false on that host; check `modules/hosts/common/apps-enable.nix:63`.

- [ ] **Step 5: Commit**

```bash
git add modules/browsers/brave-origin/apps.nix
git commit -m "feat(brave-origin): apply the shared Brave managed policy set

brave-origin shipped unpoliced while it is the enabled Brave on both hosts, so general browsing ran without
HttpsOnlyMode, BlockThirdPartyCookies, WebRtcIPHandling or any of the Default*Setting permission blocks. It reads
/etc/brave/policies, the same directory as brave, so an assertion refuses the configuration when both modules would
write extended.json.

Validation: nix eval of environment.etc.\"brave/policies/managed/extended.json\""
```

### Task 9: Define the app catalog and the option surface

**Files:**

- Create: `modules/browsers/webapps/_catalog.nix`

- Create: `modules/browsers/webapps/apps.nix`

- [ ] **Step 1: Write the catalog**

Create `modules/browsers/webapps/_catalog.nix`. It is pure data keyed by app key, so a host can override one app without rewriting the set:

```nix
/*
  Internal: default web app catalog
  Description: Default for programs.webapps.apps. Keyed by app key so a host or
  a later module can override one entry without restating the catalog. The
  leading underscore keeps this file out of module auto-discovery.

  Start URLs are bare origins. Microsoft's landing paths are locale- and
  tenant-dependent (/en-us/, /mail/, /tasks/), so pinning one ages out while the
  origin does not.

  teams.cloud.microsoft is included here where the firefoxpwa catalog excluded
  it: that exclusion was Gecko-specific (a /v2/unsupported-browser redirect) and
  does not apply to a Chromium runtime.

  Not included, verified 2026-08-04 against Gecko and to be re-tested on
  Chromium before adding: visio.cloud.microsoft redirects to
  m365.cloud.microsoft, and clipchamp.cloud.microsoft does not resolve.
*/
{
  m365 = {
    name = "Microsoft 365";
    url = "https://m365.cloud.microsoft/";
  };
  word = {
    name = "Word";
    url = "https://word.cloud.microsoft/";
  };
  excel = {
    name = "Excel";
    url = "https://excel.cloud.microsoft/";
  };
  powerpoint = {
    name = "PowerPoint";
    url = "https://powerpoint.cloud.microsoft/";
  };
  outlook = {
    name = "Outlook";
    url = "https://outlook.cloud.microsoft/";
    permissions.notifications = true;
    tray.enable = true;
    reload.enable = true;
  };
  onenote = {
    name = "OneNote";
    url = "https://onenote.cloud.microsoft/";
  };
  onedrive = {
    name = "OneDrive";
    url = "https://onedrive.cloud.microsoft/";
  };
  teams = {
    name = "Microsoft Teams";
    url = "https://teams.cloud.microsoft/";
    permissions = {
      notifications = true;
      microphone = true;
      camera = true;
      screenCapture = true;
    };
    tray.enable = true;
    reload.enable = true;
  };
}
```

- [ ] **Step 2: Write the NixOS module with the typed option surface**

Create `modules/browsers/webapps/apps.nix`:

```nix
/*
  Web apps: NixOS-scope options and managed policy
  Description: Declares programs.webapps and writes the per-origin permission
    and extension policy that every web app runs under. Launchers, per-app
    profiles and tray wrapping live in ./home.nix, which reads these options
    through osConfig.

  Mechanism:
    * Each app is a distinct Chromium instance with its own --user-data-dir, so
      no two apps share cookies, storage or extensions.
    * Permissions are denied globally and granted per origin. Chromium's
      permission policies are origin-scoped, so one host-wide file grants
      exactly the apps that declared each capability.
    * The whole file is rendered by sops-nix so an app whose origin is a secret
      never has that origin written to the Nix store. Chromium's config-dir
      loader lets one file win a repeated key outright instead of merging, so
      splitting this across a store file and a secret file would silently drop
      entries; it stays one file.

  Geolocation is deliberately absent from the permission submodule: Chromium
  ships GeolocationBlockedForUrls but no matching allowlist, so it cannot be
  granted per app the way the others can.
*/
{
  flake.nixosModules.browsers.webapps =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.webapps;

      appModule = lib.types.submodule (
        { name, ... }:
        {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Display name used for the launcher and desktop entry.";
            };

            url = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Start URL. Mutually exclusive with urlSecret. Leave null when the
                URL is a secret.
              '';
            };

            urlSecret = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "gecko_work_bookmark_url_1";
              description = ''
                Key in secrets/gecko.yaml holding the start URL. The launcher reads
                the decrypted value at runtime, so the URL never enters the store.
                Requires originSecret, because the permission policy needs an origin
                and sops templates substitute values without transforming them.
              '';
            };

            originSecret = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "gecko_work_bookmark_origin_1";
              description = ''
                Key in secrets/gecko.yaml holding the scheme://host origin of urlSecret.
                Stored separately because Chromium content-setting patterns are
                scheme/host/port only and reject a path.
              '';
            };

            icon = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "Desktop entry icon. Falls back to programs.webapps.defaultIcon.";
            };

            categories = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "Network" ];
              description = "Desktop entry categories.";
            };

            permissions = {
              microphone = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Grant getUserMedia audio. Adds the origin to AudioCaptureAllowedUrls.";
              };
              camera = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Grant getUserMedia video. Adds the origin to VideoCaptureAllowedUrls.";
              };
              notifications = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Grant the Notifications API. Adds the origin to NotificationsAllowedForUrls.";
              };
              clipboard = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Grant clipboard read. Adds the origin to ClipboardAllowedForUrls.";
              };
              screenCapture = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Grant getDisplayMedia. Adds the origin to ScreenCaptureAllowedByOrigins.";
              };
              sensors = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Grant motion and light sensors. Adds the origin to SensorsAllowedForUrls.";
              };
              windowManagement = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Grant multi-screen window placement. Adds the origin to WindowManagementAllowedForUrls.";
              };
              localFonts = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Grant local font enumeration. Adds the origin to LocalFontsAllowedForUrls.";
              };
            };

            extensions = {
              enable = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = ''
                  Web Store extension IDs active only for this app. Force-installed
                  everywhere but blocked from interacting with every origin except
                  this one, through runtime_blocked_hosts and runtime_allowed_hosts.
                '';
              };
              disable = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = ''
                  IDs from programs.webapps.defaultExtensions this app opts out of.
                  The extension stays installed but is blocked from this origin
                  through runtime_blocked_hosts.
                '';
              };
            };

            tray = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = ''
                  Launch through kdocker so the app docks to the system tray and
                  iconifies instead of closing. Keeps the instance alive, so timers,
                  service workers and notifications keep running.
                '';
              };
              icon = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "Tray icon. Falls back to icon, then programs.webapps.defaultTrayIcon.";
              };
            };

            reload = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = ''
                  Load a generated MV3 extension that reloads the app on a timer to
                  keep a login session alive. Reloads only while the window is not
                  focused, so an in-use session is never interrupted.
                '';
              };
              intervalMinutes = lib.mkOption {
                type = lib.types.ints.positive;
                default = 20;
                description = ''
                  Reload period. Chromium enforces a 0.5 minute floor on
                  chrome.alarms periods.
                '';
              };
            };

            key = lib.mkOption {
              type = lib.types.str;
              internal = true;
              readOnly = true;
              default = name;
              description = "Attribute name, used for the profile directory and WM class.";
            };
          };
        }
      );
    in
    {
      options.programs.webapps = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to install declarative Chromium web apps.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.brave-origin;
          defaultText = lib.literalExpression "pkgs.brave-origin";
          description = ''
            Chromium-family browser the web apps run in. Must be a build that
            honors --load-extension, which excludes Google-branded Chrome.
          '';
        };

        browserBinary = lib.mkOption {
          type = lib.types.str;
          default = "brave-origin";
          description = "Executable name inside programs.webapps.package.";
        };

        policyFile = lib.mkOption {
          type = lib.types.str;
          default = "brave/policies/managed/webapps.json";
          description = ''
            Path under /etc for the generated web app policy. Must sit in the same
            managed directory the browser reads, and must not be the file
            programs.brave-origin.extended writes.
          '';
        };

        defaultIcon = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Desktop entry icon for apps that declare none.";
        };

        defaultTrayIcon = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Tray icon for tray-enabled apps that declare none.";
        };

        defaultExtensions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "aeblfdkhhhdcdjpifhhbdiojplfjncoa" ];
          description = ''
            Web Store extension IDs force-installed into every app profile. The
            default is 1Password; brave-origin's own Shields cover content blocking,
            so no ad blocker is listed.
          '';
        };

        secretsFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "SOPS file backing urlSecret and originSecret keys.";
        };

        apps = lib.mkOption {
          type = lib.types.attrsOf appModule;
          default = import ./_catalog.nix;
          defaultText = lib.literalExpression "import ./_catalog.nix";
          description = "Web apps to install, keyed by app key.";
        };
      };

      config = lib.mkIf cfg.enable (
        let
          policy = import ./_policy.nix {
            inherit lib;
            inherit (cfg) apps defaultExtensions;
            originPlaceholder = key: config.sops.placeholder."webapps/${key}/origin";
          };

          secretApps = lib.filterAttrs (_: app: app.originSecret != null) cfg.apps;
          secretsPresent = cfg.secretsFile != null && builtins.pathExists cfg.secretsFile;
        in
        lib.mkMerge [
          {
            assertions = lib.mapAttrsToList (key: app: {
              assertion = (app.url == null) != (app.urlSecret == null);
              message = "programs.webapps.apps.${key}: set exactly one of url or urlSecret.";
            }) cfg.apps
            ++ lib.mapAttrsToList (key: app: {
              assertion = app.urlSecret == null || app.originSecret != null;
              message = ''
                programs.webapps.apps.${key}: urlSecret requires originSecret. The permission
                policy needs a scheme://host origin and sops templates substitute values
                without transforming them, so the origin has to be its own key.
              '';
            }) cfg.apps
            ++ [
              {
                assertion = secretApps == { } || cfg.secretsFile != null;
                message = "programs.webapps: an app declares urlSecret but programs.webapps.secretsFile is null.";
              }
            ];
          }

          (lib.mkIf (secretApps == { } || secretsPresent) {
            sops.secrets = lib.mapAttrs' (
              key: app:
              lib.nameValuePair "webapps/${key}/origin" {
                sopsFile = cfg.secretsFile;
                key = app.originSecret;
                mode = "0400";
              }
            ) secretApps;

            sops.templates."webapps-policy" = {
              content = builtins.toJSON policy;
              mode = "0444";
            };

            environment.etc.${cfg.policyFile}.source = config.sops.templates."webapps-policy".path;
            environment.systemPackages = [ cfg.package ];
          })

          (lib.mkIf (secretApps != { } && cfg.secretsFile != null && !secretsPresent) {
            warnings = [
              "programs.webapps: ${toString cfg.secretsFile} is missing; skipping the web app policy and launchers."
            ];
          })
        ]
      );
    };
}
```

- [ ] **Step 3: Verify the module parses before the policy generator exists**

```bash
nix-instantiate --parse modules/browsers/webapps/apps.nix > /dev/null && echo PARSE-OK
```

Expected: `PARSE-OK`. Evaluation still fails until Task 10 adds `_policy.nix`.

- [ ] **Step 4: Commit**

```bash
git add modules/browsers/webapps/_catalog.nix modules/browsers/webapps/apps.nix
git commit -m "feat(webapps): declare the web app option surface and catalog

Keyed attrset with a typed submodule so a host overrides one app by key instead of restating the catalog. Teams is
included where the firefoxpwa catalog excluded it: that exclusion was a Gecko-only /v2/unsupported-browser redirect.
Geolocation is absent from the permission submodule because Chromium ships GeolocationBlockedForUrls with no matching
allowlist, so it cannot be granted per origin.

Validation: nix-instantiate --parse"
```

### Task 10: Generate the Chromium policy from the app set

**Files:**

- Create: `modules/browsers/webapps/_policy.nix`

- [ ] **Step 1: Write the policy generator**

Create `modules/browsers/webapps/_policy.nix`:

```nix
/*
  Internal: web app managed policy generator
  Description: Pure function from the programs.webapps.apps set to the Chromium
  policy attrset written at /etc/<browser>/policies/managed/webapps.json. Kept
  free of module `config` so ./policy-check.nix can call it on fixtures. The
  leading underscore keeps this file out of module auto-discovery.

  Key sets must stay disjoint from _chromium-hardening.nix. Chromium's
  config-dir loader lets one file win a repeated key outright rather than
  merging, so a list policy named in both files loses one file's entries
  silently. ./policy-check.nix asserts the disjointness.

  The capture toggles (AudioCaptureAllowed, VideoCaptureAllowed,
  ScreenCaptureAllowed) live here rather than in the hardening set so each
  deny-by-default sits next to the allowlist that opens it.
*/
{
  lib,
  apps,
  defaultExtensions,
  # key -> string. Returns a sops placeholder for apps whose origin is secret.
  originPlaceholder,
}:
let
  # scheme://host from a URL, dropping any path. Chromium content-setting
  # patterns are scheme/host/port only and reject a path component.
  originFromUrl =
    url:
    let
      parts = lib.splitString "/" url;
    in
    assert lib.assertMsg (lib.length parts >= 3)
      "webapps: cannot derive an origin from '${url}'; expected scheme://host/...";
    "${lib.elemAt parts 0}//${lib.elemAt parts 2}";

  originOf = app: if app.originSecret != null then originPlaceholder app.key else originFromUrl app.url;

  # Origins of every app that granted `perm`, sorted for a stable file.
  granted =
    perm:
    lib.sort (a: b: a < b) (
      lib.mapAttrsToList (_: originOf) (lib.filterAttrs (_: app: app.permissions.${perm}) apps)
    );

  allOrigins = lib.sort (a: b: a < b) (lib.mapAttrsToList (_: originOf) apps);

  hostPattern = origin: "${origin}/*";

  # Default extensions: force-installed everywhere, blocked from the origins of
  # apps that opted out. runtime_blocked_hosts stops interaction; it does not
  # uninstall, which is the behaviour wanted for a password manager.
  defaultEntries = lib.listToAttrs (
    map (
      id:
      lib.nameValuePair id (
        {
          installation_mode = "force_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        }
        // (
          let
            optedOut = lib.mapAttrsToList (_: originOf) (
              lib.filterAttrs (_: app: lib.elem id app.extensions.disable) apps
            );
          in
          lib.optionalAttrs (optedOut != [ ]) {
            runtime_blocked_hosts = lib.sort (a: b: a < b) (map hostPattern optedOut);
          }
        )
      )
    ) defaultExtensions
  );

  # Per-app extensions: force-installed, blocked everywhere, allowed only on the
  # origins of the apps that asked for them.
  perAppIds = lib.unique (lib.concatMap (app: app.extensions.enable) (lib.attrValues apps));

  perAppEntries = lib.listToAttrs (
    map (
      id:
      lib.nameValuePair id {
        installation_mode = "force_installed";
        update_url = "https://clients2.google.com/service/update2/crx";
        runtime_blocked_hosts = [ "*://*/*" ];
        runtime_allowed_hosts = lib.sort (a: b: a < b) (
          map hostPattern (
            lib.mapAttrsToList (_: originOf) (lib.filterAttrs (_: app: lib.elem id app.extensions.enable) apps)
          )
        );
      }
    ) perAppIds
  );
in
{
  # Deny by default. Each pairs with the allowlist directly below it.
  AudioCaptureAllowed = false;
  AudioCaptureAllowedUrls = granted "microphone";

  VideoCaptureAllowed = false;
  VideoCaptureAllowedUrls = granted "camera";

  ScreenCaptureAllowed = false;
  ScreenCaptureAllowedByOrigins = granted "screenCapture";

  # The Default*Setting counterparts are set to 2 (block) by
  # _chromium-hardening.nix; only the allowlists belong in this file.
  NotificationsAllowedForUrls = granted "notifications";
  ClipboardAllowedForUrls = granted "clipboard";
  SensorsAllowedForUrls = granted "sensors";
  WindowManagementAllowedForUrls = granted "windowManagement";
  LocalFontsAllowedForUrls = granted "localFonts";

  # Web app origins are the only sites these instances ever load, so nothing
  # else needs an exemption.
  URLAllowlist = allOrigins;

  ExtensionSettings = {
    "*" = {
      installation_mode = "blocked";
      blocked_install_message = "Web app extensions are managed through Nix and cannot be installed from the browser.";
    };
  }
  // defaultEntries
  // perAppEntries;
}
```

- [ ] **Step 2: Verify the generator against the catalog by hand**

```bash
nix eval --impure --json --expr '
  let
    lib = (import <nixpkgs> {}).lib;
    catalog = import ./modules/browsers/webapps/_catalog.nix;
    withDefaults = lib.mapAttrs (key: app: {
      inherit key;
      url = app.url or null;
      originSecret = app.originSecret or null;
      permissions = {
        microphone = false; camera = false; notifications = false; clipboard = false;
        screenCapture = false; sensors = false; windowManagement = false; localFonts = false;
      } // (app.permissions or {});
      extensions = { enable = []; disable = []; } // (app.extensions or {});
    }) catalog;
  in import ./modules/browsers/webapps/_policy.nix {
    inherit lib;
    apps = withDefaults;
    defaultExtensions = [ "aeblfdkhhhdcdjpifhhbdiojplfjncoa" ];
    originPlaceholder = key: "PLACEHOLDER-${key}";
  }' | jq -S .
```

Expected: `AudioCaptureAllowedUrls` and `VideoCaptureAllowedUrls` each contain exactly `https://teams.cloud.microsoft`; `NotificationsAllowedForUrls` contains `https://outlook.cloud.microsoft` and `https://teams.cloud.microsoft`; every other allowlist is `[]`; no origin carries a trailing path.

- [ ] **Step 3: Commit**

```bash
git add modules/browsers/webapps/_policy.nix
git commit -m "feat(webapps): generate per-origin permission and extension policy

Deny-by-default capture toggles sit next to the allowlist that opens them, so a granted capability is one line of
diff. Per-app extension scoping uses runtime_blocked_hosts and runtime_allowed_hosts rather than separate policy
files, because Chromium's config-dir loader lets one file win a repeated key outright instead of merging it.

Validation: nix eval of the generator against _catalog.nix, asserting teams holds the only capture grants"
```

### Task 11: Generate the keep-alive extension

**Files:**

- Create: `modules/browsers/webapps/_reload-extension.nix`

- [ ] **Step 1: Write the extension builder**

Create `modules/browsers/webapps/_reload-extension.nix`:

```nix
/*
  Internal: generated MV3 keep-alive extension
  Description: Builds an unpacked extension per web app that reloads the app on
  a timer so a login session does not time out. Loaded with --load-extension,
  which brave-origin honors because it is not a GOOGLE_CHROME_BRANDING build and
  the hardening set pins SafeBrowsingProtectionLevel to standard rather than
  enhanced. The leading underscore keeps this file out of module auto-discovery.

  The reload is skipped while the app window has focus, so an in-use session is
  never interrupted mid-input. chrome.alarms wakes the service worker after
  Chromium has idled it, which is what keeps the timer running while the window
  sits iconified in the tray.

  Each app loads its own copy: --load-extension applies to a browser instance,
  and every app is its own instance under its own --user-data-dir, so the
  interval is baked in at build time instead of being read from storage.
*/
{ lib, runCommand }:
{
  key,
  appName,
  intervalMinutes,
}:
assert lib.assertMsg (intervalMinutes >= 1)
  "webapps: reload.intervalMinutes for '${key}' must be at least 1; Chromium floors chrome.alarms periods at 0.5 minutes.";
runCommand "webapp-reload-${key}"
  {
    passthru = { inherit key intervalMinutes; };
    meta.description = "Keep-alive reload extension for the ${appName} web app";
  }
  ''
    mkdir -p "$out"

    cat > "$out/manifest.json" <<'MANIFEST'
    {
      "manifest_version": 3,
      "name": "${appName} keep-alive",
      "version": "1.0.0",
      "description": "Reloads ${appName} every ${toString intervalMinutes} minutes while it is not in use.",
      "permissions": ["alarms", "tabs"],
      "background": { "service_worker": "service-worker.js" }
    }
    MANIFEST

    cat > "$out/service-worker.js" <<'WORKER'
    // Period is baked in at build time: each web app loads its own copy of this
    // extension into its own --user-data-dir, so there is nothing to configure.
    const PERIOD_MINUTES = ${toString intervalMinutes};
    const ALARM = "webapp-keepalive";

    function schedule() {
      chrome.alarms.create(ALARM, { periodInMinutes: PERIOD_MINUTES });
    }

    chrome.runtime.onInstalled.addListener(schedule);
    chrome.runtime.onStartup.addListener(schedule);

    chrome.alarms.onAlarm.addListener(async (alarm) => {
      if (alarm.name !== ALARM) return;

      // Skip while the app is in the foreground so a reload never lands
      // mid-input. getLastFocused throws when no window is open, which is the
      // tray-iconified case and exactly when the reload should proceed.
      try {
        const win = await chrome.windows.getLastFocused();
        if (win && win.focused) return;
      } catch (e) {
        // No window to inspect; fall through and reload.
      }

      const tabs = await chrome.tabs.query({});
      for (const tab of tabs) {
        if (tab.id !== undefined) {
          chrome.tabs.reload(tab.id, { bypassCache: false });
        }
      }
    });
    WORKER
  ''
```

- [ ] **Step 2: Build one and inspect it**

```bash
nix eval --impure --raw --expr '
  let pkgs = import <nixpkgs> {}; in
  (import ./modules/browsers/webapps/_reload-extension.nix {
    inherit (pkgs) lib runCommand;
  }) { key = "teams"; appName = "Microsoft Teams"; intervalMinutes = 20; }
' | xargs -I{} sh -c 'jq . {}/manifest.json && head -5 {}/service-worker.js'
```

Expected: valid JSON with `manifest_version: 3` and `permissions: ["alarms","tabs"]`, and a service worker whose `PERIOD_MINUTES` is `20`.

- [ ] **Step 3: Verify the interval assertion fires**

```bash
nix eval --impure --raw --expr '
  let pkgs = import <nixpkgs> {}; in
  (import ./modules/browsers/webapps/_reload-extension.nix {
    inherit (pkgs) lib runCommand;
  }) { key = "bad"; appName = "Bad"; intervalMinutes = 0; }
' 2>&1 | rg -q 'must be at least 1' && echo ASSERT-OK
```

Expected: `ASSERT-OK`.

- [ ] **Step 4: Commit**

```bash
git add modules/browsers/webapps/_reload-extension.nix
git commit -m "feat(webapps): generate a per-app MV3 keep-alive extension

chrome.alarms wakes the service worker after Chromium idles it, which is what keeps the timer running while the window
sits iconified in the tray. The reload is skipped while the window has focus so it never lands mid-input;
getLastFocused throwing is the no-window case and falls through to reload deliberately.

Validation: nix eval building the extension for teams, asserting the manifest shape and the baked interval"
```

### Task 12: Build the launchers and desktop entries

**Files:**

- Create: `modules/browsers/webapps/home.nix`

- [ ] **Step 1: Write the Home Manager module**

Create `modules/browsers/webapps/home.nix`:

```nix
/*
  Web apps: launchers, per-app profiles and tray integration
  Description: Builds one launcher per web app declared in programs.webapps
  (NixOS scope, ./apps.nix) and registers a desktop entry for it. Each launcher
  runs the browser against its own --user-data-dir, which is what keeps cookies,
  storage and extensions separate between apps and keeps a session usable across
  launches.

  Tray-enabled apps launch through kdocker rather than the browser directly, so
  closing the window iconifies to the tray instead of exiting. The instance
  stays alive, which is what keeps service workers, the keep-alive timer and
  notifications running.

  An app whose start URL is a secret reads it from the decrypted file at launch
  rather than having it baked into the launcher, so the URL never enters the
  store. The origin still reaches the managed policy through a separate secret
  key; see ./apps.nix.
*/
{
  flake.homeManagerModules.browsers.webapps =
    {
      config,
      lib,
      pkgs,
      osConfig,
      secretsRoot,
      ...
    }:
    let
      osCfg = osConfig.programs.webapps or { };
      enabled = osCfg.enable or false;
      apps = osCfg.apps or { };

      geckoFile = secretsRoot + "/gecko.yaml";
      geckoFileExists = builtins.pathExists geckoFile;

      dataRoot = "${config.xdg.dataHome}/webapps";

      secretApps = lib.filterAttrs (_: app: app.urlSecret != null) apps;
      needsSecrets = secretApps != { };

      mkReloadExtension = pkgs.callPackage ./_reload-extension.nix { };

      resolveIcon =
        app:
        if app.icon != null then
          app.icon
        else if (osCfg.defaultIcon or null) != null then
          osCfg.defaultIcon
        else
          null;

      resolveTrayIcon =
        app:
        if app.tray.icon != null then
          app.tray.icon
        else if (osCfg.defaultTrayIcon or null) != null then
          osCfg.defaultTrayIcon
        else
          resolveIcon app;

      browser = lib.getExe' osCfg.package osCfg.browserBinary;

      # The launcher that actually starts the browser. Named webapp-<key> so it
      # is also usable from a shell or an i3 binding.
      mkBrowserLauncher =
        key: app:
        let
          profileDir = "${dataRoot}/${key}";
          reloadExtension =
            if app.reload.enable then
              mkReloadExtension {
                inherit key;
                appName = app.name;
                inherit (app.reload) intervalMinutes;
              }
            else
              null;
          urlExpr =
            if app.urlSecret != null then
              ''"$(cat ${lib.escapeShellArg config.sops.secrets."webapps/${key}/url".path})"''
            else
              lib.escapeShellArg app.url;
        in
        pkgs.writeShellApplication {
          name = "webapp-${key}";
          runtimeInputs = [ osCfg.package ] ++ lib.optional (app.urlSecret != null) pkgs.coreutils;
          text = ''
            install -d -m 700 ${lib.escapeShellArg profileDir}
            exec ${browser} \
              --user-data-dir=${lib.escapeShellArg profileDir} \
              --class=${lib.escapeShellArg "WebApp-${key}"} \
              ${lib.optionalString (
                reloadExtension != null
              ) "--load-extension=${lib.escapeShellArg "${reloadExtension}"} \\"}
              --app=${urlExpr} \
              "$@"
          '';
        };

      # kdocker launches and docks the command it is given. A separate wrapper
      # rather than kdocker flags inline in the desktop entry, so the browser
      # arguments are never re-parsed by kdocker's own option handling.
      mkTrayLauncher =
        key: app: browserLauncher:
        let
          icon = resolveTrayIcon app;
        in
        pkgs.writeShellApplication {
          name = "webapp-${key}-tray";
          runtimeInputs = [
            pkgs.kdocker
            browserLauncher
          ];
          text = ''
            exec kdocker \
              ${lib.optionalString (icon != null) "-i ${lib.escapeShellArg "${icon}"} \\"}
              -z \
              -q \
              -l \
              -d 30 \
              ${lib.getExe browserLauncher}
          '';
        };

      launchers = lib.mapAttrs (
        key: app:
        let
          browserLauncher = mkBrowserLauncher key app;
        in
        {
          inherit browserLauncher;
          entry = if app.tray.enable then mkTrayLauncher key app browserLauncher else browserLauncher;
        }
      ) apps;

      active = enabled && (!needsSecrets || geckoFileExists);
    in
    {
      config = lib.mkMerge [
        (lib.mkIf active {
          sops.secrets = lib.mapAttrs' (
            key: app:
            lib.nameValuePair "webapps/${key}/url" {
              sopsFile = geckoFile;
              key = app.urlSecret;
              mode = "0400";
            }
          ) secretApps;

          # Both are installed: the tray wrapper is what the desktop entry runs,
          # and the plain launcher stays on PATH so an i3 binding or a shell can
          # start the app without the tray.
          home.packages = lib.concatMap (l: lib.unique [ l.browserLauncher l.entry ]) (
            lib.attrValues launchers
          );

          xdg.enable = lib.mkDefault true;

          xdg.desktopEntries = lib.mapAttrs (key: app: {
            inherit (app) name categories;
            exec = "${lib.getExe launchers.${key}.entry} %U";
            icon = let i = resolveIcon app; in if i == null then "browser" else "${i}";
            type = "Application";
            terminal = false;
            settings = {
              StartupWMClass = "WebApp-${key}";
            };
          }) apps;

          # Created before first launch so a profile never inherits a permissive
          # umask. Same treatment and ordering as modules/home/gecko-secrets.nix.
          home.activation.ensureWebappProfileDirs =
            lib.hm.dag.entryBetween [ "sops-nix" ] [ "writeBoundary" ]
              (
                ''
                  install -d -m 700 ${lib.escapeShellArg dataRoot}
                ''
                + lib.concatMapStrings (key: ''
                  install -d -m 700 ${lib.escapeShellArg "${dataRoot}/${key}"}
                '') (lib.attrNames apps)
              );
        })

        (lib.mkIf (enabled && needsSecrets && !geckoFileExists) {
          warnings = [
            "programs.webapps declares an app with a secret URL but ${toString geckoFile} is missing; skipping the web app launchers."
          ];
        })
      ];
    };
}
```

- [ ] **Step 2: Register the module with the shared browser set**

In `modules/hosts/common/home-manager-apps.nix`, add `"webapps"` to `sharedBrowserNames`:

```nix
  sharedBrowserNames = [
    "firefox"
    "google-chrome"
    "librewolf"
    "ungoogled-chromium"
    "webapps"
  ];
```

- [ ] **Step 3: Verify the launcher text**

```bash
nix fmt
nix eval --raw "path:.#nixosConfigurations.tpnix.config.home-manager.users.vx.home.packages" \
  --accept-flake-config --apply 'ps: builtins.concatStringsSep "\n" (map (p: p.name) ps)' 2>/dev/null \
  | rg '^webapp-'
```

Expected: one `webapp-<key>` per catalog app, plus `webapp-outlook-tray` and `webapp-teams-tray`.

- [ ] **Step 4: Commit**

```bash
git add modules/browsers/webapps/home.nix modules/hosts/common/home-manager-apps.nix
git commit -m "feat(webapps): build per-app launchers, profiles and tray entries

Each launcher runs the browser against its own --user-data-dir, which is the isolation the firefoxpwa installer never
configured. Tray apps go through a kdocker wrapper rather than kdocker flags inline in the desktop entry, so the
browser arguments are never re-parsed by kdocker's own option handling. A secret start URL is read from the decrypted
file at launch instead of being baked into the launcher.

Validation: nix eval of home.packages, asserting one launcher per catalog app plus the two tray wrappers"
```

### Task 13: Wire the hosts-common baseline

**Files:**

- Create: `modules/browsers/webapps/enable.nix`

- Modify: `modules/meta/cache-roots.nix`

- [ ] **Step 1: Write the baseline toggle**

Create `modules/browsers/webapps/enable.nix`. It uses the shared-host-module pattern from CLAUDE.md rather than the flat app catalog, because `programs.webapps.enable` is not a `<name>.extended.enable` entry and the catalog's duplicate-override check keys on that shape:

`secretsRoot` is already a NixOS-scope module argument: `modules/configurations/nixos.nix:42` passes it, and `modules/hosts/common/duplicati.nix:9`, `fonts.nix:8` and `usbguard.nix:6` already consume it that way. No change to `modules/configurations/nixos.nix` is needed.

```nix
/*
  Web apps: common-host baseline
  Description: Turns programs.webapps on for every host that shares the common
  baseline, and points it at the SOPS file backing secret start URLs. Kept out
  of modules/hosts/common/apps-enable.nix because that catalog is keyed on
  <name>.extended.enable and modules/hosts/common/checks.nix compares against
  that shape.
*/
{ lib, ... }:
let
  body =
    { secretsRoot, ... }:
    {
      programs.webapps = {
        enable = lib.mkOverride 1100 true;
        secretsFile = lib.mkOverride 1100 (secretsRoot + "/gecko.yaml");
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
```

- [ ] **Step 2: Add brave-origin to the cache roots**

In `modules/meta/cache-roots.nix`, insert `"brave-origin"` as the first element of `hostPackageNames`, immediately above `"burpsuite"`, keeping the list alphabetical. Every other element stays untouched.

```bash
rg -n -A3 'hostPackageNames = \[' modules/meta/cache-roots.nix
```

Expected before the edit: the list opens with `"burpsuite"`. After the edit, confirm exactly one line was added and it is in the right place:

```bash
git diff --stat modules/meta/cache-roots.nix
rg -n -A2 'hostPackageNames = \[' modules/meta/cache-roots.nix
```

Expected: `1 insertion(+)`, and the list now opens with `"brave-origin"` followed by `"burpsuite"`.

- [ ] **Step 3: Validate the full configuration evaluates**

```bash
nix fmt
nix flake check path:. --accept-flake-config --no-build --offline
nix build "path:.#nixosConfigurations.tpnix.config.system.build.toplevel" --no-link
```

Expected: both succeed.

- [ ] **Step 4: Commit**

```bash
git add modules/browsers/webapps/enable.nix modules/meta/cache-roots.nix
git commit -m "feat(webapps): enable the baseline and cache brave-origin

programs.webapps.enable stays out of modules/hosts/common/apps-enable.nix because that catalog is keyed on
<name>.extended.enable and modules/hosts/common/checks.nix compares against that shape. brave-origin joins the cache
roots now that every web app launcher depends on it.

Validation: nix flake check path:. --accept-flake-config --no-build --offline;
nix build path:.#nixosConfigurations.tpnix.config.system.build.toplevel"
```

### Task 14: Add the policy regression check

**Files:**

- Create: `modules/browsers/webapps/policy-check.nix`

- Create: `modules/browsers/webapps/check-fixtures/policy.json`

- [ ] **Step 1: Write the check**

Create `modules/browsers/webapps/policy-check.nix`:

```nix
/*
  Check: web app managed policy (modules/browsers/webapps/_policy.nix).

  Three things this pins that nothing else would catch:

  - The generated policy against a committed fixture, so a permission silently
    appearing or disappearing from an app is a diff rather than a surprise at
    the next switch.
  - Disjointness against _chromium-hardening.nix. Both files land in
    /etc/brave/policies/managed, and Chromium's config-dir loader lets one file
    win a repeated key outright rather than merging it, so a key named in both
    silently loses one file's value.
  - That no app is granted a capability it did not declare. The fixture alone
    would not catch a generator that leaked every origin into every allowlist,
    because the fixture would simply be regenerated with the bug in it.
*/
{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks."browsers/webapps-policy" =
        let
          catalog = import ./_catalog.nix;

          # The submodule defaults the module system would apply, restated here
          # so the generator can be called without evaluating a whole host.
          withDefaults = lib.mapAttrs (key: app: {
            inherit key;
            url = app.url or null;
            originSecret = app.originSecret or null;
            permissions = {
              microphone = false;
              camera = false;
              notifications = false;
              clipboard = false;
              screenCapture = false;
              sensors = false;
              windowManagement = false;
              localFonts = false;
            }
            // (app.permissions or { });
            extensions = {
              enable = [ ];
              disable = [ ];
            }
            // (app.extensions or { });
          }) catalog;

          policy = import ./_policy.nix {
            inherit lib;
            apps = withDefaults;
            defaultExtensions = [ "aeblfdkhhhdcdjpifhhbdiojplfjncoa" ];
            originPlaceholder = key: "PLACEHOLDER-${key}";
          };

          hardening = (import ../_chromium-hardening.nix).policies;
          overlap = lib.intersectLists (lib.attrNames policy) (lib.attrNames hardening);

          # Every allowlist, paired with the permission that fills it.
          allowlists = {
            AudioCaptureAllowedUrls = "microphone";
            VideoCaptureAllowedUrls = "camera";
            ScreenCaptureAllowedByOrigins = "screenCapture";
            NotificationsAllowedForUrls = "notifications";
            ClipboardAllowedForUrls = "clipboard";
            SensorsAllowedForUrls = "sensors";
            WindowManagementAllowedForUrls = "windowManagement";
            LocalFontsAllowedForUrls = "localFonts";
          };

          originOf =
            app:
            let
              parts = lib.splitString "/" app.url;
            in
            "${lib.elemAt parts 0}//${lib.elemAt parts 2}";

          expectedFor =
            perm:
            lib.sort (a: b: a < b) (
              lib.mapAttrsToList (_: originOf) (lib.filterAttrs (_: app: app.permissions.${perm}) withDefaults)
            );

          unexpectedGrants = lib.filter (name: policy.${name} != expectedFor allowlists.${name}) (
            lib.attrNames allowlists
          );

          actual = (pkgs.formats.json { }).generate "webapps-policy.json" policy;
        in
        assert lib.assertMsg (overlap == [ ])
          "browsers/webapps-policy: keys ${toString overlap} appear in both _policy.nix and _chromium-hardening.nix; Chromium's config-dir loader lets one file win a repeated key outright, so one file's value would be lost silently";
        assert lib.assertMsg (unexpectedGrants == [ ])
          "browsers/webapps-policy: ${toString unexpectedGrants} do not match the origins that declared the matching permission";
        assert lib.assertMsg (policy.AudioCaptureAllowed == false && policy.VideoCaptureAllowed == false && policy.ScreenCaptureAllowed == false)
          "browsers/webapps-policy: capture must be denied by default";
        pkgs.runCommand "webapps-policy-check" { } ''
          if ! ${lib.getExe pkgs.diffutils} -u ${./check-fixtures/policy.json} ${actual}; then
            echo "browsers/webapps-policy: generated policy differs from the fixture." >&2
            echo "If the change is intended, refresh it with:" >&2
            echo "  nix build path:.#checks.\$(nix eval --raw --impure --expr builtins.currentSystem).\"browsers/webapps-policy\"" >&2
            echo "  cp ${actual} modules/browsers/webapps/check-fixtures/policy.json" >&2
            exit 1
          fi
          touch "$out"
        '';
    };
}
```

- [ ] **Step 2: Generate the fixture from the current generator**

```bash
mkdir -p modules/browsers/webapps/check-fixtures
nix eval --impure --json --expr '
  let
    lib = (import <nixpkgs> {}).lib;
    catalog = import ./modules/browsers/webapps/_catalog.nix;
    withDefaults = lib.mapAttrs (key: app: {
      inherit key;
      url = app.url or null;
      originSecret = app.originSecret or null;
      permissions = {
        microphone = false; camera = false; notifications = false; clipboard = false;
        screenCapture = false; sensors = false; windowManagement = false; localFonts = false;
      } // (app.permissions or {});
      extensions = { enable = []; disable = []; } // (app.extensions or {});
    }) catalog;
  in import ./modules/browsers/webapps/_policy.nix {
    inherit lib;
    apps = withDefaults;
    defaultExtensions = [ "aeblfdkhhhdcdjpifhhbdiojplfjncoa" ];
    originPlaceholder = key: "PLACEHOLDER-${key}";
  }' | jq -S . > modules/browsers/webapps/check-fixtures/policy.json
```

- [ ] **Step 3: Read the fixture before trusting it**

```bash
jq '{
  camera: .VideoCaptureAllowedUrls,
  mic: .AudioCaptureAllowedUrls,
  notifications: .NotificationsAllowedForUrls,
  denied: [.AudioCaptureAllowed, .VideoCaptureAllowed, .ScreenCaptureAllowed],
  extensions: (.ExtensionSettings | keys)
}' modules/browsers/webapps/check-fixtures/policy.json
```

Expected: `camera` and `mic` are `["https://teams.cloud.microsoft"]`; `notifications` holds outlook and teams; `denied` is `[false,false,false]`; `extensions` is `["*","aeblfdkhhhdcdjpifhhbdiojplfjncoa"]`.

- [ ] **Step 4: Prove the check fails on a bad policy**

```bash
jq '.VideoCaptureAllowedUrls += ["https://word.cloud.microsoft"]' \
  modules/browsers/webapps/check-fixtures/policy.json > /tmp/policy-bad.json
cp modules/browsers/webapps/check-fixtures/policy.json /tmp/policy-good.json
cp /tmp/policy-bad.json modules/browsers/webapps/check-fixtures/policy.json
nix build "path:.#checks.x86_64-linux.\"browsers/webapps-policy\"" --accept-flake-config 2>&1 | rg -q 'differs from the fixture' && echo FIXTURE-DETECTS-DRIFT
cp /tmp/policy-good.json modules/browsers/webapps/check-fixtures/policy.json
```

Expected: `FIXTURE-DETECTS-DRIFT`.

- [ ] **Step 5: Run the check clean**

```bash
nix build "path:.#checks.x86_64-linux.\"browsers/webapps-policy\"" --accept-flake-config --no-link
```

Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add modules/browsers/webapps/policy-check.nix modules/browsers/webapps/check-fixtures/policy.json
git commit -m "test(webapps): pin the generated policy and the disjoint-key invariant

The fixture alone would not catch a generator that leaked every origin into every allowlist, because the fixture
would be regenerated with the bug in it, so the check also recomputes the expected grants from the catalog. The
disjointness assertion is the one that matters most: both policy files land in /etc/brave/policies/managed and
Chromium's config-dir loader lets one file win a repeated key outright rather than merging it.

Validation: planted drift in VideoCaptureAllowedUrls is reported before the clean run is trusted"
```

### Task 15: Add the Home Manager evaluation check

**Files:**

- Create: `modules/browsers/webapps/module-check.nix`

- Create: `modules/browsers/webapps/check-fixtures/gecko.yaml`

- [ ] **Step 1: Copy the non-secret fixture**

The removed `modules/browsers/firefoxpwa/module-check-fixtures/gecko.yaml` served this exact purpose. Recover it from the deletion commit:

```bash
git show "$(git log --diff-filter=D --format=%H -1 -- modules/browsers/firefoxpwa/module-check-fixtures/gecko.yaml)^:modules/browsers/firefoxpwa/module-check-fixtures/gecko.yaml" \
  > modules/browsers/webapps/check-fixtures/gecko.yaml
```

Add the origin key the new module needs. Open the file and confirm it holds non-secret placeholder values, then append:

```yaml
gecko_work_bookmark_origin_1: https://mail.example.invalid
```

- [ ] **Step 2: Write the check**

Create `modules/browsers/webapps/module-check.nix`. It mirrors the structure the firefoxpwa module check used, because that structure exists to force `lib.mkIf` blocks CI would otherwise never evaluate:

```nix
/*
  Check: the webapps Home Manager module evaluates (modules/browsers/webapps).

  home.nix guards everything behind lib.mkIf (enabled && (!needsSecrets ||
  geckoFileExists)), and CI never has the secrets submodule (see
  .github/workflows/check.yml), so every attribute inside that block, the
  launcher text, the desktop entry, the sops secret, would never be evaluated
  by nix flake check. A typo or a reference to a removed binding would reach
  main and fail only at the next real switch.

  Builds a standalone Home Manager configuration the way
  modules/home-manager/checks.nix does, with osConfig stubbed and secretsRoot
  pointed at ./check-fixtures, so the guard evaluates true here regardless of
  what the real secrets submodule holds.
*/
{
  lib,
  inputs,
  config,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    {
      checks."browsers/webapps-module-eval" =
        let
          mkHm =
            {
              webappsConfig,
              secretsRoot ? ./check-fixtures,
            }:
            inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                inputs.sops-nix.homeManagerModules.sops
                config.flake.homeManagerModules.browsers.webapps
                {
                  home = {
                    username = "hm-smoke";
                    homeDirectory = "/tmp/hm-smoke";
                    stateVersion = (lib.importJSON "${inputs.home-manager}/release.json").release;
                    enableNixpkgsReleaseCheck = false;
                  };
                  programs.home-manager.enable = true;
                  sops.validateSopsFiles = false;
                  sops.age.keyFile = "/dev/null";
                }
              ];
              extraSpecialArgs = {
                osConfig.programs.webapps = webappsConfig;
                inherit secretsRoot;
              };
            };

          baseApp = {
            icon = null;
            categories = [ "Network" ];
            permissions = {
              microphone = false;
              camera = false;
              notifications = false;
              clipboard = false;
              screenCapture = false;
              sensors = false;
              windowManagement = false;
              localFonts = false;
            };
            extensions = {
              enable = [ ];
              disable = [ ];
            };
            tray = {
              enable = false;
              icon = null;
            };
            reload = {
              enable = false;
              intervalMinutes = 20;
            };
            url = null;
            urlSecret = null;
            originSecret = null;
          };

          webappsConfig = {
            enable = true;
            package = pkgs.brave-origin;
            browserBinary = "brave-origin";
            defaultIcon = null;
            defaultTrayIcon = null;
            apps = {
              plain = baseApp // {
                key = "plain";
                name = "Plain";
                url = "https://plain.example.invalid/";
              };
              trayed = baseApp // {
                key = "trayed";
                name = "Trayed";
                url = "https://trayed.example.invalid/";
                tray = {
                  enable = true;
                  icon = null;
                };
                reload = {
                  enable = true;
                  intervalMinutes = 5;
                };
              };
              secret = baseApp // {
                key = "secret";
                name = "Secret";
                urlSecret = "gecko_work_bookmark_url_1";
                originSecret = "gecko_work_bookmark_origin_1";
              };
            };
          };

          hm = mkHm { inherit webappsConfig; };
          noGecko = mkHm {
            inherit webappsConfig;
            secretsRoot = "${./check-fixtures}/missing";
          };

          packageNames = map (p: p.name or "") hm.config.home.packages;
        in
        assert lib.assertMsg (lib.any (lib.hasInfix "gecko.yaml is missing") noGecko.config.warnings)
          "browsers/webapps-module-eval: a missing gecko.yaml must warn";
        assert lib.assertMsg (noGecko.config.sops.secrets == { })
          "browsers/webapps-module-eval: a missing gecko.yaml must not declare sops secrets";
        assert lib.assertMsg (hm.config.warnings == [ ])
          "browsers/webapps-module-eval: the enabled configuration must not warn";
        assert lib.assertMsg (lib.elem "webapp-plain" packageNames)
          "browsers/webapps-module-eval: every app must install a launcher";
        assert lib.assertMsg (lib.elem "webapp-trayed-tray" packageNames)
          "browsers/webapps-module-eval: a tray-enabled app must install a kdocker wrapper";
        assert lib.assertMsg (!lib.elem "webapp-plain-tray" packageNames)
          "browsers/webapps-module-eval: an app without tray.enable must not install a kdocker wrapper";
        assert lib.assertMsg
          (hm.config.xdg.desktopEntries.plain.settings.StartupWMClass == "WebApp-plain")
          "browsers/webapps-module-eval: desktop entries must pin StartupWMClass to the launcher --class";
        assert lib.assertMsg (builtins.hasAttr "webapps/secret/url" hm.config.sops.secrets)
          "browsers/webapps-module-eval: an app with urlSecret must declare its sops secret";
        assert lib.assertMsg (!builtins.hasAttr "webapps/plain/url" hm.config.sops.secrets)
          "browsers/webapps-module-eval: an app without urlSecret must not declare a sops secret";
        builtins.deepSeq {
          entries = hm.config.xdg.desktopEntries;
          packages = packageNames;
          secrets = lib.attrNames hm.config.sops.secrets;
          activation = hm.config.home.activation.ensureWebappProfileDirs;
          warnings = {
            enabled = hm.config.warnings;
            noGecko = noGecko.config.warnings;
          };
        } hm.config.home-files;
    };
}
```

- [ ] **Step 3: Prove each assertion can fail**

Temporarily change the tray assertion to expect `webapp-plain-tray`, run the check, and confirm it reports the failure rather than passing:

```bash
sed -i 's/lib.elem "webapp-trayed-tray" packageNames/lib.elem "webapp-plain-tray" packageNames/' \
  modules/browsers/webapps/module-check.nix
nix build "path:.#checks.x86_64-linux.\"browsers/webapps-module-eval\"" --accept-flake-config 2>&1 \
  | rg -q 'must install a kdocker wrapper' && echo ASSERTIONS-REACHABLE
sed -i 's/lib.elem "webapp-plain-tray" packageNames/lib.elem "webapp-trayed-tray" packageNames/' \
  modules/browsers/webapps/module-check.nix
```

Expected: `ASSERTIONS-REACHABLE`.

- [ ] **Step 4: Run the check clean**

```bash
nix build "path:.#checks.x86_64-linux.\"browsers/webapps-module-eval\"" --accept-flake-config --no-link
```

Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add modules/browsers/webapps/module-check.nix modules/browsers/webapps/check-fixtures/gecko.yaml
git commit -m "test(webapps): force the Home Manager module's guarded output

CI never has the secrets submodule, so everything inside home.nix's mkIf guard, the launcher text, the desktop entry
and the sops secret, would never be evaluated by nix flake check. The fixture secretsRoot makes the guard true
regardless. Assertions proven reachable by inverting the tray expectation before the clean run is trusted.

Validation: nix build path:.#checks.x86_64-linux.\"browsers/webapps-module-eval\""
```

### Task 16: Add the DMail app and its secrets

**Files:**

- Modify: `secrets/gecko.yaml` (encrypted submodule)

- Modify: `modules/browsers/webapps/_catalog.nix`

- Modify: `modules/browsers/webapps/check-fixtures/policy.json`

- [ ] **Step 1: Add the origin key to the secrets file**

`gecko_work_bookmark_url_1` already exists and is the DMail URL (see `modules/home/gecko-secrets.nix:18,26`). The policy needs a separate origin key because Chromium content-setting patterns are scheme/host/port only.

```bash
cd /home/vx/nixos/secrets
sops gecko.yaml
```

Add, using the scheme and host of `gecko_work_bookmark_url_1` with no path and no trailing slash:

```yaml
gecko_work_bookmark_origin_1: https://<host of gecko_work_bookmark_url_1>
```

- [ ] **Step 2: Add DMail to the catalog**

In `modules/browsers/webapps/_catalog.nix`, add:

```nix
  dmail = {
    name = "DMail";
    urlSecret = "gecko_work_bookmark_url_1";
    originSecret = "gecko_work_bookmark_origin_1";
    permissions.notifications = true;
    tray.enable = true;
    reload.enable = true;
  };
```

- [ ] **Step 3: Refresh the policy fixture**

The fixture generator substitutes `PLACEHOLDER-dmail` for the secret origin, so the fixture stays free of the real host:

```bash
cd /home/vx/trees/nixos/feat-chromium-webapps
nix eval --impure --json --expr '
  let
    lib = (import <nixpkgs> {}).lib;
    catalog = import ./modules/browsers/webapps/_catalog.nix;
    withDefaults = lib.mapAttrs (key: app: {
      inherit key;
      url = app.url or null;
      originSecret = app.originSecret or null;
      permissions = {
        microphone = false; camera = false; notifications = false; clipboard = false;
        screenCapture = false; sensors = false; windowManagement = false; localFonts = false;
      } // (app.permissions or {});
      extensions = { enable = []; disable = []; } // (app.extensions or {});
    }) catalog;
  in import ./modules/browsers/webapps/_policy.nix {
    inherit lib;
    apps = withDefaults;
    defaultExtensions = [ "aeblfdkhhhdcdjpifhhbdiojplfjncoa" ];
    originPlaceholder = key: "PLACEHOLDER-${key}";
  }' | jq -S . > modules/browsers/webapps/check-fixtures/policy.json
```

- [ ] **Step 4: Confirm no real host leaked into the fixture**

```bash
rg -n 'PLACEHOLDER-dmail' modules/browsers/webapps/check-fixtures/policy.json
rg -c 'cloud.microsoft|example.invalid|PLACEHOLDER' modules/browsers/webapps/check-fixtures/policy.json
git diff --stat modules/browsers/webapps/check-fixtures/policy.json
```

Expected: `PLACEHOLDER-dmail` appears in `NotificationsAllowedForUrls` and `URLAllowlist`; every origin in the file is a `cloud.microsoft` host or a placeholder. If any other hostname appears, stop and fix the generator before committing.

- [ ] **Step 5: Validate and commit**

```bash
nix fmt
nix flake check path:. --accept-flake-config --no-build --offline
git add modules/browsers/webapps/_catalog.nix modules/browsers/webapps/check-fixtures/policy.json
git -C secrets add gecko.yaml
git add secrets
git commit -m "feat(webapps): install DMail with a secret start URL

gecko_work_bookmark_url_1 already held the URL; gecko_work_bookmark_origin_1 is new because Chromium content-setting
patterns are scheme/host/port only and reject a path, and sops templates substitute values without transforming them.
The launcher reads the URL at runtime and the policy carries only the origin, so neither reaches the store.

Validation: nix flake check path:. --accept-flake-config --no-build --offline; fixture confirmed placeholder-only"
```

### Task 17: Document the module and open the PR

**Files:**

- Modify: `docs/architecture/04-home-manager.md`

- Create: `docs/reference/webapps.md`

- Regenerate: `README.md`

- [ ] **Step 1: Write the operator reference**

Create `docs/reference/webapps.md`:

````markdown
# Declarative Chromium Web Apps

`programs.webapps` installs websites as standalone apps in `brave-origin`. Each
app runs as its own browser instance under its own `--user-data-dir`, so no two
apps share cookies, storage or extensions, and a session survives across
launches.

## Adding an app

Add an entry to `modules/browsers/webapps/_catalog.nix`, or override
`programs.webapps.apps.<key>` from a host module:

```nix
programs.webapps.apps.grafana = {
  name = "Grafana";
  url = "https://grafana.example.com/";
  permissions.notifications = true;
  tray.enable = true;
  reload = {
    enable = true;
    intervalMinutes = 10;
  };
};
```

Refresh the policy fixture afterwards, or `checks."browsers/webapps-policy"`
fails with a diff:

```sh
nix build 'path:.#checks.x86_64-linux."browsers/webapps-policy"' --accept-flake-config
```

The failure message prints the exact `cp` command to refresh the fixture.

## Permissions

Everything is denied by default and granted per origin. Available toggles:

| Toggle             | Policy                           |
| ------------------ | -------------------------------- |
| `microphone`       | `AudioCaptureAllowedUrls`        |
| `camera`           | `VideoCaptureAllowedUrls`        |
| `screenCapture`    | `ScreenCaptureAllowedByOrigins`  |
| `notifications`    | `NotificationsAllowedForUrls`    |
| `clipboard`        | `ClipboardAllowedForUrls`        |
| `sensors`          | `SensorsAllowedForUrls`          |
| `windowManagement` | `WindowManagementAllowedForUrls` |
| `localFonts`       | `LocalFontsAllowedForUrls`       |

Geolocation is not offered. Chromium ships `GeolocationBlockedForUrls` but no
matching allowlist, so it cannot be granted per app; it stays blocked by
`DefaultGeolocationSetting = 2` in `modules/browsers/_chromium-hardening.nix`.

## Extensions

`programs.webapps.defaultExtensions` is force-installed into every app profile
(1Password by default). Per app:

- `extensions.disable = [ "<id>" ]` blocks a default extension from that app's
  origin through `runtime_blocked_hosts`. It stays installed but stops
  interacting with the site.
- `extensions.enable = [ "<id>" ]` force-installs an extension and blocks it
  everywhere except the origins that asked for it.

Extensions come from the Chrome Web Store so their IDs stay correct, which is
what 1Password's native messaging to the desktop app validates.

## Tray and backgrounding

`tray.enable = true` launches through `kdocker`, so closing the window
iconifies to the tray instead of exiting. The instance stays alive, which keeps
service workers, the keep-alive timer and notifications running. `tray.icon`
overrides `programs.webapps.defaultTrayIcon` per app.

This is X11 only. `kdocker` docks an X11 window into an XEmbed tray, which is
what i3bar provides.

## Session keep-alive

`reload.enable = true` loads a generated MV3 extension that reloads the app
every `reload.intervalMinutes` (default 20). The reload is skipped while the
window has focus, so an in-use session is never interrupted. Chromium floors
`chrome.alarms` periods at 0.5 minutes.

## Secret start URLs

An app whose URL must not enter the Nix store sets `urlSecret` and
`originSecret`, both keys in `secrets/gecko.yaml`. The launcher reads the URL
from the decrypted file at launch; the policy carries only the origin, because
Chromium content-setting patterns are scheme/host/port only and reject a path.

## Where the policy lands

Two files in `/etc/brave/policies/managed/`:

- `extended.json` from `modules/browsers/brave-origin/apps.nix`, the shared
  hardened set.
- `webapps.json` from `modules/browsers/webapps/apps.nix`, rendered by sops-nix,
  holding the per-origin allowlists and `ExtensionSettings`.

Their key sets must stay disjoint. Chromium's config-dir loader lets one file
win a repeated key outright rather than merging it, so a key in both silently
loses one file's value. `checks."browsers/webapps-policy"` asserts this.

Inspect what actually applied with `brave://policy`.
````

- [ ] **Step 2: Update the architecture doc**

In `docs/architecture/04-home-manager.md`, the browser-modules paragraph was already rewritten in Task 5 Step 1 to cite webapps. Confirm it reads correctly now that both files exist:

```bash
rg -n 'webapps' docs/architecture/04-home-manager.md
```

Expected: the sentence names `modules/browsers/webapps/home.nix` and `modules/browsers/webapps/apps.nix`.

- [ ] **Step 3: Regenerate managed artifacts**

```bash
nix develop path:. --accept-flake-config -c write-files --offline
git diff --stat
```

- [ ] **Step 4: Full validation**

```bash
nix fmt
nix develop path:. -c pre-commit run --all-files --hook-stage manual
nix flake check path:. --accept-flake-config --no-build --offline
nix build "path:.#nixosConfigurations.tpnix.config.system.build.toplevel" --no-link
nix build "path:.#nixosConfigurations.system76.config.system.build.toplevel" --no-link
```

Expected: all succeed.

- [ ] **Step 5: Commit and open the PR**

```bash
git add docs/reference/webapps.md docs/architecture/04-home-manager.md README.md
git commit -m "docs(webapps): document the web app module

Validation: nix flake check path:. --accept-flake-config --no-build --offline;
nix build path:.#nixosConfigurations.{tpnix,system76}.config.system.build.toplevel"
git push -u origin feat/chromium-webapps
gh pr create --title "feat(browsers): declarative Chromium web apps on brave-origin" --body "$(cat <<'EOF'
## Summary

Replaces the removed firefoxpwa subsystem with `programs.webapps`, a declarative Chromium web-app module.

- Each app is its own browser instance under its own `--user-data-dir`: no shared cookies, storage or extensions, and
  a session that survives across launches. This is the isolation the firefoxpwa installer never configured.
- Permissions are denied globally and granted per origin from the app definition, so a conferencing app gets mic and
  camera while everything else stays blocked.
- `tray.enable` launches through kdocker so the window iconifies to the tray instead of exiting, keeping service
  workers, timers and notifications alive. Icon defaults are overridable per app.
- `reload.enable` loads a generated MV3 extension that reloads on a timer, skipping the reload while the window has
  focus.
- brave-origin gains the shared hardened policy set it was running without.

Adds DMail plus the Microsoft 365 suite including Teams, which the firefoxpwa catalog excluded only because
`teams.cloud.microsoft` serves Gecko a `/v2/unsupported-browser` redirect.

Plan: `docs/drafts/chromium-webapps-plan.md`. Operator docs: `docs/reference/webapps.md`.

## Test plan

- `nix flake check path:. --accept-flake-config --no-build --offline`
- `nix build path:.#nixosConfigurations.{tpnix,system76}.config.system.build.toplevel`
- `checks."browsers/webapps-policy"`: generated policy against a fixture, recomputed grants against the catalog, and
  the disjoint-key invariant against `_chromium-hardening.nix`. Drift proven detected by planting an extra origin in
  `VideoCaptureAllowedUrls`.
- `checks."browsers/webapps-module-eval"`: forces the Home Manager module's `mkIf`-guarded output, which CI would
  otherwise never evaluate. Assertions proven reachable by inverting the tray expectation.
EOF
)"
```

### Task 18: Post-merge verification on a real host

Not part of the PR. Run after `feat/chromium-webapps` merges and the host switches.

- [ ] **Step 1: Confirm both policy files landed**

```bash
ls -la /etc/brave/policies/managed/
jq -S 'keys' /etc/brave/policies/managed/extended.json | head -20
jq -S 'keys' /etc/brave/policies/managed/webapps.json
```

Expected: two files; no key appears in both listings.

- [ ] **Step 2: Confirm the policy actually applied**

Launch any web app, open a new tab to `brave://policy`, and confirm `AudioCaptureAllowed`, `VideoCaptureAllowedUrls`, `NotificationsAllowedForUrls` and `ExtensionSettings` are listed with status OK and no conflict warnings.

- [ ] **Step 3: Confirm isolation**

```bash
ls -la "${XDG_DATA_HOME:-$HOME/.local/share}/webapps"
```

Expected: one 0700 directory per app. Sign in to two different apps and confirm neither sees the other's session.

- [ ] **Step 4: Confirm the tray and keep-alive**

Launch Teams, confirm a tray icon appears in i3bar, close the window and confirm it iconifies rather than exiting, then confirm the process survives:

```bash
pgrep -af 'user-data-dir.*webapps/teams'
```

Leave it iconified for longer than `reload.intervalMinutes` and confirm the session is still authenticated on restore.

- [ ] **Step 5: Confirm notifications**

Trigger a notification from Outlook or Teams and confirm dunst renders it. Check attribution:

```bash
dunstctl history | jq -r '.data[0][] | {appname, summary}' 2>/dev/null | head
```

- [ ] **Step 6: Record any deviation**

If a Microsoft origin redirects out of its own host, or Visio and Clipchamp now resolve on Chromium, update
`modules/browsers/webapps/_catalog.nix` and refresh the policy fixture in a follow-up.

______________________________________________________________________

## Self-Review

**Spec coverage.** Every stated requirement maps to a task:

| Requirement                                                           | Where                                                         |
| --------------------------------------------------------------------- | ------------------------------------------------------------- |
| Complete firefoxpwa cleanup including extension and CLI               | Tasks 2-6                                                     |
| Idiomatic, modular, reusable for many future apps                     | Tasks 9-12; keyed submodule plus a pure generator             |
| Working integrated notifications                                      | `permissions.notifications`, Task 10; verified Task 18 Step 5 |
| Opt-in backgrounding with a tray icon, default overridable per app    | `tray.{enable,icon}` plus `defaultTrayIcon`, Tasks 9 and 12   |
| Explicit per-app permissions, disabled by default                     | Task 10; deny-by-default plus per-origin allowlists           |
| Per-app profile, no shared cookies, sessions reused                   | Task 12; `--user-data-dir` per app                            |
| Configurable reload to prevent login timeout, works in the background | Task 11; `chrome.alarms` survives service-worker idling       |
| brave-origin as the base                                              | Tasks 7-8; verified it reads `/etc/brave/policies`            |
| Default extensions with per-app add and override                      | Task 10; `runtime_blocked_hosts` / `runtime_allowed_hosts`    |

**Known gaps, stated rather than hidden.**

- Geolocation cannot be granted per app. Chromium has no allowlist counterpart to `GeolocationBlockedForUrls`. Documented in `docs/reference/webapps.md` and omitted from the submodule rather than silently accepted and ignored.
- kdocker is X11 only. This matches the current i3 and lightdm setup (`modules/apps/i3wm/nixos.nix:75`) but would need replacing under Wayland.
- Each running app is a separate browser instance, roughly 250-400 MB baseline. Same cost firefoxpwa would have had with per-site profiles, but it bounds how many apps are worth leaving resident.
- `--load-extension` availability depends on the build not being Google-branded and on Enhanced Safe Browsing being off. Both hold for brave-origin under the hardened set (`SafeBrowsingProtectionLevel = 1`), but switching `programs.webapps.package` to Chrome would silently disable the keep-alive extension. Task 9's `package` option documents the constraint; consider an assertion if a second browser is ever supported.
- Visio and Clipchamp are excluded pending a Chromium re-test (Task 18 Step 6).

**Type consistency.** `key`, `name`, `url`, `urlSecret`, `originSecret`, `permissions.*`, `extensions.{enable,disable}`, `tray.{enable,icon}` and `reload.{enable,intervalMinutes}` are used identically in `_catalog.nix`, `apps.nix`, `_policy.nix`, `home.nix`, `policy-check.nix` and `module-check.nix`. The `originPlaceholder` argument has the same `key -> string` signature at both call sites (`apps.nix` and the two checks).
