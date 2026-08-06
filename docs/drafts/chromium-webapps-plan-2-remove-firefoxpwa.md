# Chromium Web Apps, Phase 2: Remove firefoxpwa

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Phase 2 of 3.** The series replaces the firefoxpwa subsystem with a declarative Chromium web-app module on brave-origin, one PR per phase:

- Phase 1: `docs/drafts/chromium-webapps-plan-1-salvage.md`. Must be merged before this phase starts.
- Phase 2, this file: delete the firefoxpwa subsystem and unwire every reference to it.
- Phase 3: `docs/drafts/chromium-webapps-plan-3-implement.md`, which also carries the decisions table, the verified facts and the self-review for the whole series.

**Goal:** Remove PWAsForFirefox entirely: the module tree, the DMail installer derivation, the runtime policy overlay, the AMO extension pin and its weekly workflow, the cache root, and the gecko-side wiring. Nothing replaces it in this phase; the Chromium module arrives in phase 3, and the M365 catalog carries over there as data.

**Tech Stack:** Nix (flake-parts, Dendritic pattern), Home Manager, GitHub Actions.

______________________________________________________________________

## Decisions that bind this phase

Locked before writing this plan. Do not relitigate during execution. The full table for the series is in `docs/drafts/chromium-webapps-plan-3-implement.md`.

| Decision     | Choice                            | Rationale                                                   |
| ------------ | --------------------------------- | ----------------------------------------------------------- |
| PR structure | Three PRs                         | Salvage, remove, implement.                                 |
| Catalog      | DMail + full M365 including Teams | Teams was excluded from #435 only because it rejects Gecko. |

The isolation the subsystem's complexity paid for was never configured: `packages/firefoxpwa-dmail-install` called `firefoxpwa site install` with no `--profile`, and PWAsForFirefox installs into the shared default profile when none is given. Removal loses no working isolation.

### On line-number anchors

This plan spans three sequential PRs, so file contents shift under it. Every `path:line` below is a hint, not an address. Re-locate the target before editing:

```bash
rg -n '<the string the plan quotes>' <the file the plan names>
```

If the string is gone, stop and re-read the file rather than editing by line number.

______________________________________________________________________

## File Structure

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

______________________________________________________________________

## Tasks

Do not start until the phase 1 PR (`docs/drafts/chromium-webapps-plan-1-salvage.md`) has merged. Every step here is a deletion or an unwiring; no behavior is added.

### Task 2: Delete the firefoxpwa-owned files

**Files:**

- Delete: `modules/browsers/firefoxpwa/`, `packages/firefoxpwa-dmail-install/`, `modules/custom-overlays/firefoxpwa.nix`, `modules/browsers/_firefoxpwa-extension-pin.json`, `scripts/update-firefoxpwa-extension.py`, `.github/workflows/update-firefoxpwa-extension.yml`

- [ ] **Step 1: Create the worktree**

```bash
cd /home/vx/nixos
git fetch origin main
git worktree add "$HOME/trees/nixos/refactor-drop-firefoxpwa" -b "refactor/drop-firefoxpwa" origin/main
cd "$HOME/trees/nixos/refactor-drop-firefoxpwa"
```

- [ ] **Step 2: Record the pre-removal reference set**

```bash
rg -n -i 'firefoxpwa|PWAsForFirefox' --hidden -g '!.git' -g '!docs/nixos-manual' -g '!docs/drafts' \
  | rg -v '^docs/index\.md:[0-9]+:.*chromium-webapps-plan' \
  > /tmp/firefoxpwa-before.txt
wc -l /tmp/firefoxpwa-before.txt
cut -d: -f1 /tmp/firefoxpwa-before.txt | sort -u | wc -l
```

`docs/drafts` is excluded throughout this task. The three plan files for this series are themselves in the repo and
name firefoxpwa on nearly every page, so a sweep that includes them can never reach zero and the removal could never
be certified complete.

The `docs/index.md` filter is the same exclusion reaching one level further out. `docs/AGENTS.md` requires an index
row per page, so the index links each of the three plan files by name and one of those names contains the string.
Only rows pointing at a `chromium-webapps-plan` file are dropped, not the whole file: a row that named a real
firefoxpwa page would still be reported, and so would that page. A future edit that puts the word back into an index
summary shows up as an extra hit rather than disappearing, which is the direction this sweep should fail in.

Record the two numbers rather than comparing them against a figure written here: the counts move whenever a draft or
a workflow is edited, and a stale figure would either mask a missed reference or fail for an unrelated reason. The
saved file is the checklist Task 4 Step 7 `comm`s its own sweep against; nothing else reads it.

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

- [ ] **Step 5: Verify the edited gecko files still parse**

`nix flake check` cannot pass here, so do not run it. Task 2 deleted
`modules/browsers/firefoxpwa/` while every host-side reference to it is still in the tree:
`modules/hosts/common/home-manager-apps.nix` lists `"firefoxpwa"` in `sharedBrowserNames` and its
`getBrowserModule` throws when the module is absent, `modules/hosts/common/apps-enable.nix` and
`modules/tpnix/apps-enable.nix` assign `programs.firefoxpwa.*` options that no longer exist, and
`modules/meta/cache-roots.nix` resolves `programs.firefoxpwa.extended.package`. Task 4 removes all four and runs the
full check at its Step 8. Running it here reports Task 4's outstanding work as a failure of this task and sends the
operator into the `_gecko-*.nix` files for an error that is not there.

```bash
nix run path:.#formatter.x86_64-linux -- .
nix-instantiate --parse modules/browsers/_gecko-extension-data.nix \
  modules/browsers/_gecko-extensions.nix modules/browsers/_gecko-mk-profile.nix \
  modules/browsers/firefox/home.nix modules/browsers/librewolf/home.nix > /dev/null
```

Expected: exit 0. That is what this task can prove on its own. A leftover reference in these five files surfaces at
Task 4 Step 8 as an undefined-variable error.

Tasks 2 and 3 therefore do not evaluate standalone, which this series treats as a defect elsewhere: Task 10 Step 4
exists so that every phase 3 commit evaluates from a clean checkout. The alternative is to unwire first and delete
last, which is achievable here, `modules/browsers/firefoxpwa/` reads none of the gecko bindings Task 3 removes, so the
order 3, 4, 2 would leave every commit evaluating. It is not taken because the removal is one atomic `rip` whose
recoverability the baseline sweep in Task 2 Step 2 is written against, and because renumbering the phase would
invalidate the cross-references the other two plan files and the PR body make to these task numbers. The cost is
bounded and stated: two commits in this phase evaluate only as part of the sequence, and the phase does not merge
until Task 4 Step 8 passes.

- [ ] **Step 6: Commit**

```bash
git add modules/browsers/_gecko-extension-data.nix modules/browsers/_gecko-extensions.nix \
  modules/browsers/_gecko-mk-profile.nix modules/browsers/firefox/home.nix modules/browsers/librewolf/home.nix
git commit -m "refactor(browsers)!: drop firefoxpwa wiring from the gecko stack

Removes the PWAsForFirefox management extension entry, the AMO pin reader and its stale-pin throw, the Tab Reloader
add-on (installed only into PWA runtime profiles, never the regular browsers), and the firefoxpwaRuntimePolicies set
the deleted overlay injected. firefox and librewolf lose the firefoxpwa native-messaging host.

Validation: nix-instantiate --parse over the five edited files. The full flake check runs in the next commit, which
removes the host-side references that still name the module tree deleted in the previous one."
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
rg -n -i 'firefoxpwa|PWAsForFirefox' --hidden -g '!.git' -g '!docs/nixos-manual' -g '!docs/drafts' \
  | rg -v '^docs/index\.md:[0-9]+:.*chromium-webapps-plan' \
  > /tmp/firefoxpwa-after.txt
cat /tmp/firefoxpwa-after.txt

# Files in the Task 2 baseline that no longer match. Everything the removal
# was supposed to reach has to be here.
comm -23 <(cut -d: -f1 /tmp/firefoxpwa-before.txt | sort -u) \
  <(cut -d: -f1 /tmp/firefoxpwa-after.txt | sort -u)
```

Expected: the first command prints only `docs/architecture/04-home-manager.md` and
`docs/reference/binary-cache-coverage.md`, handled in Task 5. The `comm` prints every other file the baseline held,
which is the checklist Task 2 Step 2 recorded: a file listed there and absent from this output is one the removal
missed.

- [ ] **Step 8: Validate and commit**

```bash
nix run path:.#formatter.x86_64-linux -- .
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

In `docs/architecture/04-home-manager.md`, the sentence beginning "A sibling file can extend the same `browsers.<name>` key" cites firefoxpwa as its worked example. Drop the firefoxpwa clause so the paragraph ends:

```markdown
A sibling file can extend the same `browsers.<name>` key, merged the same way `apps.stylix-gui` is above.
```

Do not substitute the webapps files here. This phase is deletions and unwirings only, and
`modules/browsers/webapps/home.nix` and `modules/browsers/webapps/nixos.nix` do not exist until phase 3 Tasks 12 and
9\. Naming them now would ship architecture documentation citing files that are not in the tree, and it would stay
that way for as long as phase 3 takes, or permanently if phase 3 is abandoned. Phase 3 Task 17 Step 2 adds the
replacement example in the same PR that creates the files.

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
rg -n -i 'firefoxpwa|PWAsForFirefox' --hidden -g '!.git' -g '!docs/nixos-manual' -g '!docs/drafts' \
  | rg -v '^docs/index\.md:[0-9]+:.*chromium-webapps-plan'
```

Expected: no output. The `docs/drafts` exclusion is what makes that reachable: this plan and its two siblings live in
the repo and name firefoxpwa throughout, and `docs/index.md` links each of them by name. Both exclusions are
explained at Task 2 Step 2.

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
`docs/drafts/chromium-webapps-plan-3-implement.md`.

## Test plan

- `nix flake check path:. --accept-flake-config --no-build --offline`
- `nix build path:.#nixosConfigurations.tpnix.config.system.build.toplevel`
- `rg -i 'firefoxpwa|PWAsForFirefox'` returns nothing outside `docs/nixos-manual/`, `docs/drafts/` and the
  `docs/index.md` rows that link them: the manual mirror, this migration plan, and the index entry `docs/AGENTS.md`
  requires for it
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
