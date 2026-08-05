# Chromium Web Apps, Phase 3: Implement the web-app module

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Phase 3 of 3.** The series replaces the firefoxpwa subsystem with a declarative Chromium web-app module on brave-origin, one PR per phase:

- Phase 1: `docs/drafts/chromium-webapps-plan-1-salvage.md`.
- Phase 2: `docs/drafts/chromium-webapps-plan-2-remove-firefoxpwa.md`. Must be merged before this phase starts.
- Phase 3, this file: build the module. It carries the decisions table, the verified facts and the self-review for the whole series.

**Goal:** Replace the firefoxpwa subsystem with a declarative Chromium web-app module on brave-origin that gives every app its own isolated profile, per-origin permissions, opt-in tray backgrounding, and opt-in session keep-alive.

**Architecture:** A NixOS-scope module owns the managed enterprise policy (permissions and extensions) written into `/etc/brave/policies/managed/`; a Home Manager module owns per-app launchers, `--user-data-dir` isolation, desktop entries, and kdocker tray wrapping. App definitions live in one typed keyed attrset that both scopes read. No installer script, no systemd unit, no runtime state reconciliation.

**Tech Stack:** Nix (flake-parts, Dendritic pattern), Home Manager, sops-nix, brave-origin (Chromium 1.93.x), Chromium enterprise policy, MV3 extensions, kdocker.

______________________________________________________________________

## Decisions Recorded

Locked before writing this plan. Do not relitigate during execution.

| Decision        | Choice                                           | Rationale                                                                                                                                                                |
| --------------- | ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Base browser    | `brave-origin`                                   | Verified reads `/etc/brave/policies` (binary strings); honors `--load-extension` because it is not a `GOOGLE_CHROME_BRANDING` build; already enabled on both hosts.      |
| Isolation       | per-app `--user-data-dir`                        | Complete cookie and storage separation. NOT extension separation: `ExtensionSettings` is managed policy and therefore browser-wide.                                      |
| Extensions      | Hybrid                                           | Third-party from the Web Store via `ExtensionSettings` (correct IDs, 1Password native messaging works); only the generated keep-alive extension uses `--load-extension`. |
| Tray            | kdocker per app                                  | `-i` per-app icon, `-z` keep-running, `-l` iconify on focus loss. Opt-in per app.                                                                                        |
| Keep-alive      | Generated MV3 extension, reload only when hidden | `chrome.alarms` wakes the service worker; skips the reload when the app window is focused.                                                                               |
| Secret URLs     | One sops-rendered policy file                    | Avoids Chromium's config-dir merge, where a repeated list policy has one file win outright instead of concatenating.                                                     |
| PR #435         | Close, salvage the two unrelated fixes           | The compgen and statix fixes are repo-wide and must survive.                                                                                                             |
| Catalog         | DMail + full M365 including Teams                | Teams was excluded from #435 only because it rejects Gecko.                                                                                                              |
| Policy scope    | Full hardened set plus webapp entries            | Lifted from `modules/browsers/brave/apps.nix` and shared.                                                                                                                |
| Policy reach    | Browser-wide, not app-scoped                     | Chromium reads one managed directory per browser. `webapps.json` therefore binds every `brave-origin` instance including the daily driver. Consequences below.           |
| Keep-alive ID   | Pinned by a committed manifest `key`             | An unpacked extension's ID is a hash of its store path, so it changes every rebuild. A pinned ID is allowlistable in `ExtensionSettings` and stops profile-litter.       |
| Option shape    | Keyed attrset with submodule                     | Per-key override without rewriting the catalog.                                                                                                                          |
| NixOS file name | `webapps/nixos.nix`, not `webapps/apps.nix`      | `modules/meta/hooks/apps-catalog-sync.nix` treats every `modules/browsers/*/apps.nix` as a catalog entry and demands a matching `<dir>.extended.enable` line.            |
| PR structure    | Three PRs                                        | Salvage, remove, implement.                                                                                                                                              |
| Tests           | Eval checks plus generated-artifact fixtures     | No installer shell exists in this design.                                                                                                                                |

### Consequences of a browser-wide policy

`programs.webapps` writes `/etc/brave/policies/managed/webapps.json`. Chromium
applies a managed directory per browser, not per profile or per
`--user-data-dir`, so everything in that file also binds the `brave-origin`
instance used for general browsing on both hosts. Accepted, with these effects
stated rather than discovered later:

- `AudioCaptureAllowed`, `VideoCaptureAllowed` and `ScreenCaptureAllowed` become
  hard denials with no prompt for all browsing. Only the origins listed in the
  matching `*AllowedUrls` policy, which today means `teams.cloud.microsoft`
  alone, can use mic, camera or screen share. A video call or screen share on
  any other site fails silently in `brave-origin`.
- `ExtensionSettings."*" = blocked` blocks manual extension installs in the
  daily-driver profile, and force-installs `defaultExtensions` (1Password)
  there too.
- `URLAllowlist` is additive-only in Chromium (it exempts entries from
  `URLBlocklist`), so listing the app origins does not restrict general
  browsing. It is inert here and kept only so a future `URLBlocklist` does not
  lock the apps out.

If the mic/camera denial becomes a problem for general browsing, the fix is to
split the daily driver onto `brave` and leave `brave-origin` to the web apps, or
to drop the capture denies from `_policy.nix` and rely on per-site prompts. Both
are follow-ups, not part of this plan.

### Verified facts this plan depends on

- `brave-origin` binary contains the string `/etc/brave/policies`. Reproduce: `strings -a "$(nix eval --impure --raw --expr 'with import <nixpkgs> {}; "${brave-origin}"')/opt/brave.com/brave-origin/brave" | rg '^/etc/brave'`
- `--load-extension` is refused only under `BUILDFLAG(GOOGLE_CHROME_BRANDING)` and under Enhanced Safe Browsing. The hardened policy set pins `SafeBrowsingProtectionLevel = 1` (standard), so it stays available.
- Policy names and types confirmed against the Chromium policy registry: `AudioCaptureAllowed` (bool), `VideoCaptureAllowed` (bool), `ScreenCaptureAllowed` (bool), `DefaultNotificationsSetting` (int), `DefaultClipboardSetting` (int), `DefaultSensorsSetting` (int), `DefaultWindowManagementSetting` (int), `DefaultLocalFontsSetting` (int), `ExtensionSettings` (dict), `BackgroundModeEnabled` (bool).
- Allowlist policies that exist: `AudioCaptureAllowedUrls`, `VideoCaptureAllowedUrls`, `NotificationsAllowedForUrls`, `ClipboardAllowedForUrls`, `ScreenCaptureAllowedByOrigins`, `SensorsAllowedForUrls`, `WindowManagementAllowedForUrls`, `LocalFontsAllowedForUrls`.
- **Geolocation has no allowlist policy.** Only `GeolocationBlockedForUrls` and `PreciseGeolocationAllowedForUrls` exist. Geolocation is therefore block-only in this design and is deliberately absent from the permission submodule.
- `kdocker` 6.2 flags used: `-i <file>` custom icon, `-z` keep running with no windows, `-q` quiet, `-l` iconify on focus lost, `-d <sec>` command start timeout.
- `modules/meta/hooks/apps-catalog-sync.nix` collects catalog entries with `find modules/browsers -mindepth 2 -maxdepth 2 -type f -name apps.nix ! -path "*/_*/*"` and requires each result to have a `<dir>.extended.enable` line in `modules/hosts/common/apps-enable.nix`. A NixOS-scope file named `webapps/apps.nix` would therefore fail `pre-commit run --all-files --hook-stage manual`. The module is named `webapps/nixos.nix`, matching the existing `modules/apps/i3wm/nixos.nix` precedent.
- `pkgs.diffutils` declares no `meta.mainProgram`, so `lib.getExe pkgs.diffutils` resolves to a nonexistent `bin/diffutils`. The package ships `diff`, `cmp`, `diff3` and `sdiff`; use `lib.getExe' pkgs.diffutils "diff"`.
- An unpacked extension loaded with `--load-extension` gets an ID derived from the absolute path unless `manifest.json` carries a `key`. With a `key`, the ID is derived from that public key instead and stays stable across rebuilds.

### Facts still to verify before implementing

Two assumptions carry the design and are not yet proven. Verify each at the step
that names it and record the outcome in the plan before continuing.

- **Does `ExtensionSettings."*" = blocked` also block `--load-extension`?** Chromium's
  unpacked loader consults the same `ExtensionManagement` installation mode that
  `ExtensionSettings` sets, which would block the generated keep-alive extension
  outright. Task 10 Step 0 tests this on a real `brave-origin` before the policy
  generator is written. The pinned-ID design exists so the answer can be `yes`
  without reworking the plan.
- **Is `ScreenCaptureAllowedByOrigins` honored by this Brave build?** It is
  present in the Chromium policy registry, but Brave has removed or renamed
  capture policies before. Task 18 Step 2 reads `brave://policy` for a conflict
  or unknown-policy warning on every key this plan writes.

### On line-number anchors

This plan spans three sequential PRs, so file contents shift under it. Every
`path:line` in this document is a hint, not an address. The one exception is the
`sed -n '40,161p'` extraction in Task 7 Step 2, which is followed by an explicit
boundary check. Everywhere else, re-locate the target before editing:

```bash
rg -n '<the string the plan quotes>' <the file the plan names>
```

If the string is gone, stop and re-read the file rather than editing by line
number.

______________________________________________________________________

## File Structure

### PR 3: implementation (files created)

| File                                                  | Responsibility                                                                 |
| ----------------------------------------------------- | ------------------------------------------------------------------------------ |
| `modules/browsers/_chromium-hardening.nix`            | The hardened policy set, shared by brave and brave-origin. Pure data.          |
| `modules/browsers/webapps/_catalog.nix`               | Default app catalog. Pure data, no `lib`.                                      |
| `modules/browsers/webapps/_keepalive-key.nix`         | Committed public key and derived extension ID for the keep-alive extension.    |
| `modules/browsers/webapps/_policy.nix`                | Pure function: apps attrset to Chromium policy attrset.                        |
| `modules/browsers/webapps/_check-apps.nix`            | Single source of the fixture-generation shim; used by the check and the shell. |
| `modules/browsers/webapps/_reload-extension.nix`      | Pure function: builds the per-app MV3 keep-alive extension derivation.         |
| `modules/browsers/webapps/nixos.nix`                  | NixOS module: options, sops policy template, `environment.etc`.                |
| `modules/browsers/webapps/home.nix`                   | Home Manager module: launchers, data dirs, desktop entries, tray.              |
| `modules/browsers/webapps/enable.nix`                 | hosts-common baseline toggle.                                                  |
| `modules/browsers/webapps/policy-check.nix`           | Flake check: generated policy vs fixture, plus the disjoint-key invariant.     |
| `modules/browsers/webapps/keepalive-id-check.nix`     | Flake check: the transcribed extension ID matches its committed public key.    |
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

## Tasks

Do not start until the phase 2 PR (`docs/drafts/chromium-webapps-plan-2-remove-firefoxpwa.md`) has merged.

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

The pre-refactor value comes from `git show HEAD:` rather than from `git stash`.
A plain `git stash` would work here only because `_chromium-hardening.nix` is
still untracked at this point, it would leave a stash entry behind, and dropping
that entry is a forbidden operation under the repo's safety rules. Swapping the
file content in place has none of those properties.

Between the swap and the restore the only copy of the refactor is
`/tmp/brave-apps-refactored.nix`, and the gap spans a full host evaluation. The
restore therefore runs from a `trap` rather than from the next line: a Ctrl-C or
a crashed `nix eval` in that window would otherwise leave the working tree
holding the `HEAD` version with the refactor stranded in `/tmp`, which is
exactly the failure `git stash` could not produce. The `git diff --stat` below
only catches that if the operator reaches it.

```bash
nix fmt
nix eval --json "path:.#nixosConfigurations.tpnix.config.programs.brave.extended.managedPolicies" \
  --accept-flake-config 2>/dev/null | jq -S . > /tmp/brave-policies-after.json

cp modules/browsers/brave/apps.nix /tmp/brave-apps-refactored.nix
trap 'cp /tmp/brave-apps-refactored.nix modules/browsers/brave/apps.nix' EXIT INT TERM
git show HEAD:modules/browsers/brave/apps.nix > modules/browsers/brave/apps.nix
nix eval --json "path:.#nixosConfigurations.tpnix.config.programs.brave.extended.managedPolicies" \
  --accept-flake-config 2>/dev/null | jq -S . > /tmp/brave-policies-before.json
cp /tmp/brave-apps-refactored.nix modules/browsers/brave/apps.nix
trap - EXIT INT TERM

diff /tmp/brave-policies-before.json /tmp/brave-policies-after.json
git diff --stat modules/browsers/brave/apps.nix
```

Expected: `diff` produces no output, and `git diff --stat` still shows the
refactor, confirming the restore landed. `path:.` copies untracked files, so the
unused `_chromium-hardening.nix` sitting in the tree during the `before` eval is
harmless: the leading underscore keeps it out of module auto-discovery and the
`HEAD` version of `brave/apps.nix` does not import it.

If `/tmp/brave-policies-before.json` is empty or malformed, the eval failed
rather than produced a different value. Re-run it without `2>/dev/null` and read
the error before continuing.

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

- Create: `modules/browsers/webapps/nixos.nix`

The NixOS-scope file is `nixos.nix`, not `apps.nix`.
`modules/meta/hooks/apps-catalog-sync.nix` globs
`modules/browsers/*/apps.nix` and requires each hit to carry a
`<dir>.extended.enable` line in `modules/hosts/common/apps-enable.nix`;
`programs.webapps.enable` is deliberately not that shape (see Task 13), so an
`apps.nix` here would fail `pre-commit run --all-files --hook-stage manual` in
Task 17. `modules/apps/i3wm/nixos.nix` is the existing precedent for the name.

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

Create `modules/browsers/webapps/nixos.nix`:

```nix
/*
  Web apps: NixOS-scope options and managed policy
  Description: Declares programs.webapps and writes the per-origin permission
    and extension policy that every web app runs under. Launchers, per-app
    profiles and tray wrapping live in ./home.nix, which reads these options
    through osConfig.

  Mechanism:
    * Each app is a distinct Chromium instance with its own --user-data-dir, so
      no two apps share cookies or storage. Extensions are NOT isolated: a
      managed ExtensionSettings policy is browser-wide, so defaultExtensions is
      installed into every profile and only interaction is scoped, through
      runtime_blocked_hosts.
    * Permissions are denied browser-wide and granted per origin. Chromium reads
      one managed directory per browser, so this file also binds the
      brave-origin instance used for general browsing, not just the web apps.
      See "Consequences of a browser-wide policy" in the plan.
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
            inherit (import ./_keepalive-key.nix) keepAliveExtensionId;
            originPlaceholder = key: config.sops.placeholder."webapps/${key}/origin";
          };

          secretApps = lib.filterAttrs (_: app: app.originSecret != null) cfg.apps;
          secretsPresent = cfg.secretsFile != null && builtins.pathExists cfg.secretsFile;
        in
        lib.mkMerge [
          {
            # Ungated: a host without the secrets submodule still gets the
            # browser. Only the policy file depends on sops being able to
            # resolve the secret origins.
            environment.systemPackages = [ cfg.package ];

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
nix-instantiate --parse modules/browsers/webapps/nixos.nix > /dev/null && echo PARSE-OK
find modules/browsers -mindepth 2 -maxdepth 2 -type f -name apps.nix ! -path '*/_*/*' -printf '%h\n' \
  | sed 's|.*/||' | rg -q '^webapps$' \
  && echo "STOP: apps-catalog-sync will demand a webapps.extended.enable entry" \
  || echo CATALOG-HOOK-CLEAR
```

Expected: `PARSE-OK` and `CATALOG-HOOK-CLEAR`. Evaluation still fails until
Task 10 adds `_policy.nix` and Task 11 adds `_keepalive-key.nix`.

- [ ] **Step 4: Commit**

```bash
git add modules/browsers/webapps/_catalog.nix modules/browsers/webapps/nixos.nix
git commit -m "feat(webapps): declare the web app option surface and catalog

Keyed attrset with a typed submodule so a host overrides one app by key instead of restating the catalog. Teams is
included where the firefoxpwa catalog excluded it: that exclusion was a Gecko-only /v2/unsupported-browser redirect.
Geolocation is absent from the permission submodule because Chromium ships GeolocationBlockedForUrls with no matching
allowlist, so it cannot be granted per origin. The file is nixos.nix rather than apps.nix because
modules/meta/hooks/apps-catalog-sync.nix reads every modules/browsers/*/apps.nix as a catalog entry and demands a
matching <dir>.extended.enable line, which programs.webapps.enable is not.

Validation: nix-instantiate --parse"
```

### Task 10: Generate the Chromium policy from the app set

**Files:**

- Create: `modules/browsers/webapps/_policy.nix`

- Create: `modules/browsers/webapps/_check-apps.nix`

**Ordering:** both files created here import
`modules/browsers/webapps/_keepalive-key.nix`, which Task 11 Step 1 generates.
Run Task 11 Step 1 first, or nothing in this task evaluates. The tasks stay in
this order because the policy generator is what explains why the key has to be
pinned at all.

- [ ] **Step 0: Settle whether `ExtensionSettings` blocks `--load-extension`**

Blocking. Chromium routes unpacked loads through the same `ExtensionManagement`
installation-mode lookup that `ExtensionSettings` populates, so
`"*" = { installation_mode = "blocked"; }` plausibly blocks the generated
keep-alive extension too. That is not proven, and the answer decides whether the
policy needs an explicit allowlist entry. Test it before writing the generator:

```bash
tmp="$(mktemp -d)"
mkdir -p "$tmp/ext" "$tmp/profile" "$tmp/pol"

cat > "$tmp/ext/manifest.json" <<'EOF'
{
  "manifest_version": 3,
  "name": "load-extension probe",
  "version": "1.0.0",
  "background": { "service_worker": "sw.js" }
}
EOF
printf 'console.log("probe loaded");\n' > "$tmp/sw.js"
cp "$tmp/sw.js" "$tmp/ext/sw.js"

cat > "$tmp/pol/probe.json" <<'EOF'
{
  "ExtensionSettings": {
    "*": { "installation_mode": "blocked" }
  }
}
EOF

# Chromium reads the managed directory from a fixed path and offers no override
# for it, so the probe has to go into the host's own /etc rather than a
# throwaway root. Two consequences of that, both load-bearing:
#
#   * `zz-` sorts last, which is what makes the probe win the ExtensionSettings
#     key against extended.json. The config-dir loader picks one file's value
#     outright instead of merging, as this plan relies on elsewhere.
#   * While the file is in place, "*" = blocked binds the daily-driver
#     brave-origin too: 1Password stops being force-installed in the main
#     profile and every other extension is refused there. Left behind, that
#     persists until the next nixos-rebuild switch, so the cleanup runs from a
#     trap rather than from the last line of the block.
(
  trap 'sudo rm -f /etc/brave/policies/managed/zz-probe.json' EXIT INT TERM
  sudo install -D -m 0444 "$tmp/pol/probe.json" /etc/brave/policies/managed/zz-probe.json

  brave-origin --user-data-dir="$tmp/profile" --load-extension="$tmp/ext" \
    --no-first-run about:blank
  # In the running instance, open brave://extensions and brave://policy, then
  # close the window to reach the cleanup.
)
```

Record the result here before continuing:

- [ ] Blocked. `brave://extensions` shows the probe missing or flagged
  "Blocked by administrator". **The generator must allowlist the keep-alive
  extension ID.** Proceed with Step 1 as written and with Task 11's pinned key.
- [ ] Loaded. `brave://extensions` lists "load-extension probe".
  `--load-extension` bypasses `ExtensionSettings`. Keep the allowlist entry
  anyway: it costs one policy key and it makes the behavior explicit rather than
  dependent on a Chromium implementation detail that has changed before.

Either outcome leaves the plan unchanged. What changes is whether the keep-alive
extension silently never runs, which is the failure this step exists to prevent.

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

  Everything written here is browser-wide. Chromium applies a managed directory
  per browser, not per profile or per --user-data-dir, so these keys also bind
  the brave-origin instance used for general browsing. That is the accepted
  tradeoff; see "Consequences of a browser-wide policy" in the plan.
*/
{
  lib,
  apps,
  defaultExtensions,
  # Stable ID of the generated keep-alive extension, from ./_keepalive-key.nix.
  keepAliveExtensionId,
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

  # Additive only: URLAllowlist exempts entries from URLBlocklist and does not
  # restrict anything on its own. Nothing here narrows general browsing; it is
  # kept so a future URLBlocklist cannot lock the apps out.
  URLAllowlist = allOrigins;

  ExtensionSettings = {
    "*" = {
      installation_mode = "blocked";
      blocked_install_message = "Web app extensions are managed through Nix and cannot be installed from the browser.";
    };

    # The generated keep-alive extension is loaded with --load-extension, and
    # Chromium routes unpacked loads through the same installation-mode lookup
    # this policy fills, so "*" = blocked would otherwise refuse it. The ID is
    # pinned by the manifest key in ./_keepalive-key.nix; without that pin it
    # would be a hash of the store path and unlistable here.
    ${keepAliveExtensionId} = {
      installation_mode = "allowed";
    };
  }
  // defaultEntries
  // perAppEntries;
}
```

- [ ] **Step 2: Write the fixture shim once**

The generator has to be callable outside the module system, which means the
submodule defaults have to be restated somewhere. They were restated four times
in the first draft of this plan: in the shell command below, in Task 14's
`policy-check.nix`, in Task 14's fixture regeneration, and in Task 16's fixture
refresh. Four copies drift. They live in one file instead.

Create `modules/browsers/webapps/_check-apps.nix`:

```nix
/*
  Internal: the app set as ./_policy.nix sees it, outside the module system
  Description: ./nixos.nix builds this shape through lib.types.submodule
  defaults, which needs a whole host evaluation. Checks and the fixture-refresh
  command need the same shape from _catalog.nix alone, so the defaults are
  restated here once rather than at every call site. The leading underscore
  keeps this file out of module auto-discovery.

  MAINTENANCE: these defaults duplicate the submodule in ./nixos.nix and the
  default of programs.webapps.defaultExtensions. Changing either option's
  default without changing this file makes the fixture describe a policy the
  hosts do not get. Add the option here in the same commit.
*/
{ lib }:
let
  catalog = import ./_catalog.nix;
in
rec {
  apps = lib.mapAttrs (key: app: {
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

  defaultExtensions = [ "aeblfdkhhhdcdjpifhhbdiojplfjncoa" ];

  # Fixtures must never carry a real secret origin.
  originPlaceholder = key: "PLACEHOLDER-${key}";

  inherit (import ./_keepalive-key.nix) keepAliveExtensionId;

  policy = import ./_policy.nix {
    inherit
      lib
      apps
      defaultExtensions
      originPlaceholder
      keepAliveExtensionId
      ;
  };
}
```

The one thing that stays duplicated on purpose is Task 14's independent
recomputation of the expected grants. Sharing that with the generator would make
the check assert that the generator agrees with itself.

- [ ] **Step 3: Verify the generator against the catalog by hand**

```bash
nix eval --impure --json --expr '
  (import ./modules/browsers/webapps/_check-apps.nix {
    lib = (import <nixpkgs> {}).lib;
  }).policy' | jq -S .
```

Expected: `AudioCaptureAllowedUrls` and `VideoCaptureAllowedUrls` each contain exactly `https://teams.cloud.microsoft`; `NotificationsAllowedForUrls` contains `https://outlook.cloud.microsoft` and `https://teams.cloud.microsoft`; every other allowlist is `[]`; no origin carries a trailing path; `ExtensionSettings` holds `*`, the 1Password ID and the keep-alive ID.

This step depends on Task 11's `_keepalive-key.nix`. Either do Task 11 Step 1
first, or stub the file with the real key once Task 11 generates it and re-run
this step before committing.

- [ ] **Step 4: Commit**

```bash
git add modules/browsers/webapps/_policy.nix modules/browsers/webapps/_check-apps.nix
git commit -m "feat(webapps): generate per-origin permission and extension policy

Deny-by-default capture toggles sit next to the allowlist that opens them, so a granted capability is one line of
diff. Per-app extension scoping uses runtime_blocked_hosts and runtime_allowed_hosts rather than separate policy
files, because Chromium's config-dir loader lets one file win a repeated key outright instead of merging it. The
keep-alive extension ID is allowlisted explicitly: Chromium routes --load-extension through the same
installation-mode lookup ExtensionSettings fills, so \"*\" = blocked would otherwise refuse it silently.

Validation: nix eval of the generator against _catalog.nix, asserting teams holds the only capture grants"
```

### Task 11: Generate the keep-alive extension

**Files:**

- Create: `modules/browsers/webapps/_keepalive-key.nix`

- Create: `modules/browsers/webapps/_reload-extension.nix`

- [ ] **Step 1: Pin the extension ID**

Without a `key` in `manifest.json`, Chromium derives an unpacked extension's ID
from the SHA-256 of its absolute path. Every rebuild moves the store path, so
the ID changes on every rebuild. Three consequences, all fixed by one committed
public key:

- The ID cannot be named in `ExtensionSettings`, so `"*" = blocked` has nothing
  to make an exception for (Task 10 Step 0).
- Each persistent profile under `~/.local/share/webapps/<key>` accumulates a
  fresh extension registration per rebuild, since the old ID never matches.
- `brave://extensions` shows a different ID each time, so there is nothing
  stable to check against during verification.

With a `key`, the ID is derived from that public key and never moves. Only the
public half is used; unpacked extensions are never signed, so the private key is
generated, used once to derive the public key, and discarded.

```bash
priv="$(mktemp)"
openssl genrsa -out "$priv" 2048 2>/dev/null

pubkey="$(openssl rsa -in "$priv" -pubout -outform DER 2>/dev/null | base64 -w0)"

# Chromium's ID: first 128 bits of SHA-256 over the DER public key, each hex
# nibble mapped 0-9a-f to a-p.
extid="$(openssl rsa -in "$priv" -pubout -outform DER 2>/dev/null \
  | sha256sum | cut -c1-32 | tr '0-9a-f' 'a-p')"

rip "$priv"

printf 'publicKey  = %s\nextensionId = %s\n' "$pubkey" "$extid"
```

Create `modules/browsers/webapps/_keepalive-key.nix` with those two values:

```nix
/*
  Internal: identity of the generated keep-alive extension
  Description: An unpacked extension's ID is a hash of its absolute path unless
  manifest.json carries a `key`, in which case the ID is derived from that
  public key instead. The generated keep-alive extension needs a stable ID: it
  is loaded with --load-extension into a browser whose ExtensionSettings policy
  blocks everything not named, and its store path changes on every rebuild. The
  leading underscore keeps this file out of module auto-discovery.

  This is a public key only. Unpacked extensions are never signed, so the
  matching private key was generated once, used to derive these two values, and
  discarded. Regenerating it changes the extension ID, which orphans the
  registration in every existing app profile.

  keepAliveExtensionId is the first 128 bits of SHA-256 over the DER-encoded
  public key with each hex nibble mapped 0-9a-f to a-p. ./keepalive-id-check.nix
  recomputes it rather than trusting the value transcribed here.
*/
{
  publicKey = "<base64 DER SubjectPublicKeyInfo from the command above>";
  keepAliveExtensionId = "<32-character a-p ID from the command above>";
}
```

One key serves every app. The apps never coexist in a profile, so a shared ID
cannot collide, and one entry in `ExtensionSettings` covers all of them.

- [ ] **Step 2: Check the transcribed ID against the key**

A wrong ID here fails silently: the extension loads under its real ID, the
policy allowlists a different one, and the keep-alive is blocked with no error
anywhere in the Nix build. Recompute it in a derivation rather than trusting the
paste. Create `modules/browsers/webapps/keepalive-id-check.nix`:

```nix
/*
  Check: the keep-alive extension ID matches its public key.

  _keepalive-key.nix carries both a base64 DER public key and the extension ID
  Chromium derives from it. Nix cannot decode base64, so the ID is transcribed
  by hand and a typo would be invisible: the extension would load under its real
  ID while ExtensionSettings allowlists a different one, and the keep-alive
  would be blocked with nothing in the build to say so.
*/
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks."browsers/webapps-keepalive-id" =
        let
          inherit (import ./_keepalive-key.nix) publicKey keepAliveExtensionId;
        in
        pkgs.runCommand "webapps-keepalive-id-check"
          {
            nativeBuildInputs = [ pkgs.coreutils ];
            inherit publicKey keepAliveExtensionId;
          }
          ''
            computed="$(printf '%s' "$publicKey" | base64 -d \
              | sha256sum | cut -c1-32 | tr '0-9a-f' 'a-p')"

            if [ "$computed" != "$keepAliveExtensionId" ]; then
              echo "browsers/webapps-keepalive-id: _keepalive-key.nix says the ID is" >&2
              echo "  $keepAliveExtensionId" >&2
              echo "but the public key derives" >&2
              echo "  $computed" >&2
              exit 1
            fi
            touch "$out"
          '';
    };
}
```

Prove it can fail before trusting a pass:

```bash
nix build "path:.#checks.x86_64-linux.\"browsers/webapps-keepalive-id\"" --accept-flake-config --no-link \
  && echo ID-MATCHES
sed -i 's/keepAliveExtensionId = "\(.\)/keepAliveExtensionId = "z\1/' modules/browsers/webapps/_keepalive-key.nix
nix build "path:.#checks.x86_64-linux.\"browsers/webapps-keepalive-id\"" --accept-flake-config 2>&1 \
  | rg -q 'but the public key derives' && echo ID-CHECK-REACHABLE
sed -i 's/keepAliveExtensionId = "z/keepAliveExtensionId = "/' modules/browsers/webapps/_keepalive-key.nix
nix build "path:.#checks.x86_64-linux.\"browsers/webapps-keepalive-id\"" --accept-flake-config --no-link
```

Expected: `ID-MATCHES`, then `ID-CHECK-REACHABLE`, then a clean exit 0.

- [ ] **Step 3: Write the extension builder**

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

  The manifest key pins the extension ID. Without it the ID is a hash of the
  store path, so it would change on every rebuild: unlistable in the
  ExtensionSettings policy that blocks everything unnamed, and a fresh orphaned
  registration in every persistent profile each time. One key serves every app;
  the apps never share a profile, so a shared ID cannot collide.
*/
{ lib, runCommand }:
{
  key,
  appName,
  intervalMinutes,
}:
let
  inherit (import ./_keepalive-key.nix) publicKey;
in
assert lib.assertMsg (intervalMinutes >= 1)
  "webapps: reload.intervalMinutes for '${key}' must be at least 1; Chromium floors chrome.alarms periods at 0.5 minutes.";
runCommand "webapp-reload-${key}"
  {
    passthru = {
      inherit key intervalMinutes;
      inherit (import ./_keepalive-key.nix) keepAliveExtensionId;
    };
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
      "key": "${publicKey}",
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

- [ ] **Step 4: Build one and inspect it**

```bash
nix eval --impure --raw --expr '
  let pkgs = import <nixpkgs> {}; in
  (import ./modules/browsers/webapps/_reload-extension.nix {
    inherit (pkgs) lib runCommand;
  }) { key = "teams"; appName = "Microsoft Teams"; intervalMinutes = 20; }
' | xargs -I{} sh -c 'jq . {}/manifest.json && head -5 {}/service-worker.js'
```

Expected: valid JSON with `manifest_version: 3`, `permissions: ["alarms","tabs"]` and a `key` matching `publicKey` in `_keepalive-key.nix`, and a service worker whose `PERIOD_MINUTES` is `20`.

The heredoc is quoted (`<<'MANIFEST'`), so `${publicKey}` is interpolated by Nix
before the shell ever sees it. Confirm the rendered key is the base64 blob and
not the literal string `${publicKey}`:

```bash
nix eval --impure --raw --expr '
  let pkgs = import <nixpkgs> {}; in
  (import ./modules/browsers/webapps/_reload-extension.nix {
    inherit (pkgs) lib runCommand;
  }) { key = "teams"; appName = "Microsoft Teams"; intervalMinutes = 20; }
' | xargs -I{} jq -r '.key' {}/manifest.json | head -c 32
```

Expected: a base64 prefix, conventionally starting `MIIBIjANBgkqhkiG9w0B`.

- [ ] **Step 5: Verify the interval assertion fires**

```bash
nix eval --impure --raw --expr '
  let pkgs = import <nixpkgs> {}; in
  (import ./modules/browsers/webapps/_reload-extension.nix {
    inherit (pkgs) lib runCommand;
  }) { key = "bad"; appName = "Bad"; intervalMinutes = 0; }
' 2>&1 | rg -q 'must be at least 1' && echo ASSERT-OK
```

Expected: `ASSERT-OK`.

- [ ] **Step 6: Commit**

```bash
git add modules/browsers/webapps/_keepalive-key.nix \
  modules/browsers/webapps/keepalive-id-check.nix \
  modules/browsers/webapps/_reload-extension.nix
git commit -m "feat(webapps): generate a per-app MV3 keep-alive extension

chrome.alarms wakes the service worker after Chromium idles it, which is what keeps the timer running while the window
sits iconified in the tray. The reload is skipped while the window has focus so it never lands mid-input;
getLastFocused throwing is the no-window case and falls through to reload deliberately.

The manifest carries a committed public key so the extension ID stops being a hash of the store path. Without it the
ID moves on every rebuild: ExtensionSettings has no stable ID to allowlist, and every app profile accumulates one
orphaned registration per rebuild. Nix cannot decode base64, so the ID is transcribed and
checks.\"browsers/webapps-keepalive-id\" recomputes it from the key rather than trusting the paste.

Validation: nix eval building the extension for teams, asserting the manifest shape and the baked interval;
nix build path:.#checks.x86_64-linux.\"browsers/webapps-keepalive-id\", proven reachable by corrupting the ID"
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
  runs the browser against its own --user-data-dir, which is what keeps cookies
  and storage separate between apps and keeps a session usable across launches.
  Extensions are not separated this way: ExtensionSettings is browser-wide, so
  every profile gets the same force-installed set and only interaction is scoped
  per origin. See ./nixos.nix.

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

          # Assembled as a list rather than backslash-continued lines. An
          # lib.optionalString inside a continued argument list renders an empty
          # line when the option is off, which terminates the command there and
          # leaves the rest as a second command starting with a flag. shellcheck
          # rejects that as SC2215 and writeShellApplication fails to build.
          args = [
            "--user-data-dir=${lib.escapeShellArg profileDir}"
            "--class=${lib.escapeShellArg "WebApp-${key}"}"
          ]
          ++ lib.optional (
            reloadExtension != null
          ) "--load-extension=${lib.escapeShellArg "${reloadExtension}"}"
          ++ [ "--app=${urlExpr}" ];
        in
        pkgs.writeShellApplication {
          name = "webapp-${key}";
          runtimeInputs = [ osCfg.package ] ++ lib.optional (app.urlSecret != null) pkgs.coreutils;
          text = ''
            install -d -m 700 ${lib.escapeShellArg profileDir}
            exec ${browser} ${lib.concatStringsSep " " args} "$@"
          '';
        };

      # kdocker launches and docks the command it is given. A separate wrapper
      # rather than kdocker flags inline in the desktop entry, so the browser
      # arguments are never re-parsed by kdocker's own option handling.
      mkTrayLauncher =
        key: app: browserLauncher:
        let
          icon = resolveTrayIcon app;

          # Same list-not-continuation reason as mkBrowserLauncher above. Every
          # icon default is null, so the empty case is the common one here:
          # tray.icon, defaultTrayIcon and defaultIcon all default to null.
          args = lib.optional (icon != null) "-i ${lib.escapeShellArg "${icon}"}"
          ++ [
            "-z"
            "-q"
            "-l"
            "-d"
            "30"
            (lib.getExe browserLauncher)
          ];
        in
        pkgs.writeShellApplication {
          name = "webapp-${key}-tray";
          runtimeInputs = [
            pkgs.kdocker
            browserLauncher
          ];
          text = ''
            exec kdocker ${lib.concatStringsSep " " args}
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

- [ ] **Step 3: Verify the launchers exist**

```bash
nix fmt
nix eval --raw "path:.#nixosConfigurations.tpnix.config.home-manager.users.vx.home.packages" \
  --accept-flake-config --apply 'ps: builtins.concatStringsSep "\n" (map (p: p.name) ps)' 2>/dev/null \
  | rg '^webapp-'
```

Expected: one `webapp-<key>` per catalog app, plus `webapp-outlook-tray` and `webapp-teams-tray`.

- [ ] **Step 4: Build the launchers and read one**

Step 3 proves nothing about the launcher body. `writeShellApplication` runs
`shellcheck` at build time, so a malformed command is a build failure, not an
eval failure, and eval-only validation cannot see it. This is the step that
would have caught the empty-`optionalString` line-continuation bug: it hits
every app without `reload.enable` and both tray wrappers, which is most of the
catalog.

```bash
nix build "path:.#nixosConfigurations.tpnix.config.home-manager.users.vx.home.packages" \
  --accept-flake-config --no-link
```

Expected: exit 0. A `SC2215: This flag is used as a command name` failure means
an argument list rendered empty somewhere and the command terminated early.

Then read the two shapes that differ, the no-reload app and a tray wrapper:

```bash
outdir="$(nix eval --raw --accept-flake-config \
  "path:.#nixosConfigurations.tpnix.config.home-manager.users.vx.home.packages" \
  --apply 'ps: (builtins.head (builtins.filter (p: p.name == "webapp-word") ps)).outPath')"
cat "$outdir/bin/webapp-word"

traydir="$(nix eval --raw --accept-flake-config \
  "path:.#nixosConfigurations.tpnix.config.home-manager.users.vx.home.packages" \
  --apply 'ps: (builtins.head (builtins.filter (p: p.name == "webapp-teams-tray") ps)).outPath')"
cat "$traydir/bin/webapp-teams-tray"
```

Expected: `webapp-word` is a single `exec` line carrying `--user-data-dir`,
`--class` and `--app` with no `--load-extension` and no blank continuation;
`webapp-teams-tray` is a single `exec kdocker` line with `-z -q -l -d 30` and no
`-i` (every icon default is null until one is set).

- [ ] **Step 5: Commit**

```bash
git add modules/browsers/webapps/home.nix modules/hosts/common/home-manager-apps.nix
git commit -m "feat(webapps): build per-app launchers, profiles and tray entries

Each launcher runs the browser against its own --user-data-dir, which is the isolation the firefoxpwa installer never
configured. Tray apps go through a kdocker wrapper rather than kdocker flags inline in the desktop entry, so the
browser arguments are never re-parsed by kdocker's own option handling. A secret start URL is read from the decrypted
file at launch instead of being baked into the launcher.

Both commands are assembled as argument lists rather than backslash-continued lines. An lib.optionalString inside a
continuation renders a whitespace-only line when the option is off, which ends the command there and leaves the rest
as a second command starting with a flag; shellcheck rejects that as SC2215 and writeShellApplication fails to build.

Validation: nix build of home.packages, which runs shellcheck over every launcher; webapp-word and webapp-teams-tray
read back to confirm the no-extension and no-icon shapes"
```

### Task 13: Wire the hosts-common baseline

**Files:**

- Create: `modules/browsers/webapps/enable.nix`

- Modify: `modules/meta/cache-roots.nix`

- [ ] **Step 1: Write the baseline toggle**

Create `modules/browsers/webapps/enable.nix`. It uses the shared-host-module pattern from CLAUDE.md rather than the flat app catalog, because `programs.webapps.enable` is not a `<name>.extended.enable` entry and the catalog's duplicate-override check keys on that shape.

This is the other half of the `nixos.nix` naming decision from Task 9.
`modules/meta/hooks/apps-catalog-sync.nix` reads
`modules/browsers/*/apps.nix` as the catalog and requires each hit to have a
`<dir>.extended.enable` line in `modules/hosts/common/apps-enable.nix`. Staying
out of the catalog and naming the module file `apps.nix` are mutually exclusive;
this plan stays out of the catalog.

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
nix develop path:. -c pre-commit run --all-files --hook-stage manual apps-catalog-sync
nix flake check path:. --accept-flake-config --no-build --offline
nix build "path:.#nixosConfigurations.tpnix.config.system.build.toplevel" --no-link
```

Expected: all three succeed. The catalog hook runs here rather than only in
Task 17 because this is the task that decides `programs.webapps` stays out of
`modules/hosts/common/apps-enable.nix`; if it reports `webapps` missing from the
catalog, a file under `modules/browsers/webapps/` was named `apps.nix` and needs
renaming, not a catalog entry.

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
    because the fixture would simply be regenerated with the bug in it. This is
    the one thing here that deliberately does NOT reuse ./_check-apps.nix's
    generator output; recomputing the expectation from the catalog is the whole
    point, and sharing code with the generator would make the check assert that
    the generator agrees with itself.
*/
{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks."browsers/webapps-policy" =
        let
          # The submodule defaults live in ./_check-apps.nix, not here. Four
          # copies of this shim drifted apart in the first draft of this plan.
          checkApps = import ./_check-apps.nix { inherit lib; };
          inherit (checkApps) policy;
          withDefaults = checkApps.apps;

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
        # getExe', not getExe: diffutils declares no meta.mainProgram, so
        # lib.getExe resolves to a bin/diffutils that does not exist. The
        # package ships diff, cmp, diff3 and sdiff.
        pkgs.runCommand "webapps-policy-check" { } ''
          if ! ${lib.getExe' pkgs.diffutils "diff"} -u ${./check-fixtures/policy.json} ${actual}; then
            echo "browsers/webapps-policy: generated policy differs from the fixture." >&2
            echo "If the change is intended, refresh it with:" >&2
            echo "  nix eval --impure --json --expr '(import ./modules/browsers/webapps/_check-apps.nix { lib = (import <nixpkgs> {}).lib; }).policy' \\" >&2
            echo "    | jq -S . > modules/browsers/webapps/check-fixtures/policy.json" >&2
            exit 1
          fi
          touch "$out"
        '';
    };
}
```

- [ ] **Step 2: Generate the fixture from the current generator**

Same one-liner the check prints on failure and the same one Task 16 Step 3 uses.
There is one copy of it because there is one copy of the defaults shim.

```bash
mkdir -p modules/browsers/webapps/check-fixtures
nix eval --impure --json --expr '
  (import ./modules/browsers/webapps/_check-apps.nix {
    lib = (import <nixpkgs> {}).lib;
  }).policy' | jq -S . > modules/browsers/webapps/check-fixtures/policy.json
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

keepalive_id="$(nix eval --impure --raw --expr \
  '(import ./modules/browsers/webapps/_keepalive-key.nix).keepAliveExtensionId')"
jq --arg id "$keepalive_id" '.ExtensionSettings[$id]' \
  modules/browsers/webapps/check-fixtures/policy.json
```

Expected: `camera` and `mic` are `["https://teams.cloud.microsoft"]`;
`notifications` holds outlook and teams; `denied` is `[false,false,false]`;
`extensions` is `["*","aeblfdkhhhdcdjpifhhbdiojplfjncoa"]` plus the keep-alive
ID; and the keep-alive entry is `{"installation_mode":"allowed"}`. A `null`
there means `_policy.nix` and `_keepalive-key.nix` disagree and the keep-alive
extension will be blocked at runtime with nothing to show for it.

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
  (import ./modules/browsers/webapps/_check-apps.nix {
    lib = (import <nixpkgs> {}).lib;
  }).policy' | jq -S . > modules/browsers/webapps/check-fixtures/policy.json
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
apps share cookies or storage, and a session survives across launches.

Extensions are not isolated that way. `ExtensionSettings` is a managed policy
and managed policy is browser-wide, so every profile gets the same
force-installed set; what is scoped per app is interaction, through
`runtime_blocked_hosts` and `runtime_allowed_hosts`. See
[Scope](#scope-the-policy-is-browser-wide).

## Scope: the policy is browser-wide

Chromium applies a managed policy directory per browser, not per profile and not
per `--user-data-dir`. Everything `programs.webapps` writes to
`/etc/brave/policies/managed/webapps.json` therefore also binds the
`brave-origin` instance used for general browsing.

What that means in practice:

- **Mic, camera and screen share are denied everywhere by default, with no
  prompt.** Only origins listed in the matching `*AllowedUrls` policy can use
  them, and today that is `teams.cloud.microsoft` alone. A video call or a
  screen share on any other site fails in `brave-origin`. Granting one means
  adding that origin to an app entry in `_catalog.nix`.
- **Extension installs are blocked in the daily-driver profile too**, and
  `defaultExtensions` (1Password) is force-installed there.
- `URLAllowlist` is additive: it exempts entries from `URLBlocklist` and
  restricts nothing on its own. Listing the app origins does not narrow general
  browsing.

This is deliberate hardening, not an oversight. If the capture denial gets in
the way, the two ways out are to move general browsing to `brave` and leave
`brave-origin` to the web apps, or to drop the capture denies from
`modules/browsers/webapps/_policy.nix` and go back to per-site prompts.

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
nix eval --impure --json --expr \
  '(import ./modules/browsers/webapps/_check-apps.nix { lib = (import <nixpkgs> {}).lib; }).policy' \
  | jq -S . > modules/browsers/webapps/check-fixtures/policy.json
```

The check prints that same command when it fails.

## Permissions

Everything is denied browser-wide and granted per origin, with the browser-wide
half applying to all browsing and not just the apps. Available toggles:

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

Note what `extensions.enable` does not do. `ExtensionSettings` is browser-wide,
so an extension one app asks for is installed in every profile, including the
daily driver. Only interaction is scoped. Read it as "install this everywhere,
let it run here".

Extensions come from the Chrome Web Store so their IDs stay correct, which is
what 1Password's native messaging to the desktop app validates.

The generated keep-alive extension is the exception: it is loaded from the store
with `--load-extension`, and its ID is pinned by a committed public key in
`modules/browsers/webapps/_keepalive-key.nix` so `ExtensionSettings` has a
stable ID to allow. Without that pin the ID would be a hash of the store path,
changing on every rebuild, and the extension would be blocked by the
`"*" = blocked` default. `checks."browsers/webapps-keepalive-id"` recomputes the
ID from the key, because Nix cannot decode base64 and the value is transcribed
by hand.

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
- `webapps.json` from `modules/browsers/webapps/nixos.nix`, rendered by
  sops-nix, holding the per-origin allowlists and `ExtensionSettings`.

Their key sets must stay disjoint. Chromium's config-dir loader lets one file
win a repeated key outright rather than merging it, so a key in both silently
loses one file's value. `checks."browsers/webapps-policy"` asserts this.

Inspect what actually applied with `brave://policy`.
````

- [ ] **Step 2: Update the architecture doc**

In `docs/architecture/04-home-manager.md`, the browser-modules paragraph was already rewritten in phase 2 Task 5 Step 1 to cite webapps. Confirm it reads correctly now that both files exist:

```bash
rg -n 'webapps' docs/architecture/04-home-manager.md
```

Expected: the sentence names `modules/browsers/webapps/home.nix` and `modules/browsers/webapps/nixos.nix`.

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

- Each app is its own browser instance under its own `--user-data-dir`: no shared cookies or storage, and a session
  that survives across launches. This is the isolation the firefoxpwa installer never configured.
- `tray.enable` launches through kdocker so the window iconifies to the tray instead of exiting, keeping service
  workers, timers and notifications alive. Icon defaults are overridable per app.
- `reload.enable` loads a generated MV3 extension that reloads on a timer, skipping the reload while the window has
  focus. Its ID is pinned by a committed public key so `ExtensionSettings` can allow it.
- brave-origin gains the shared hardened policy set it was running without.

Adds DMail plus the Microsoft 365 suite including Teams, which the firefoxpwa catalog excluded only because
`teams.cloud.microsoft` serves Gecko a `/v2/unsupported-browser` redirect.

## Scope of the policy

Read this before switching. The permission policy is **browser-wide, not app-scoped**. Chromium applies a managed
directory per browser, so `/etc/brave/policies/managed/webapps.json` binds every `brave-origin` instance including
the daily driver:

- Mic, camera and screen capture become hard denials with no prompt for all browsing. The only exception is
  `teams.cloud.microsoft`. Video calls and screen shares on any other site fail in `brave-origin`.
- Extension installs are blocked in the daily-driver profile, and 1Password is force-installed there.
- Extensions are not isolated per app either: `extensions.enable` installs everywhere and scopes only interaction,
  through `runtime_blocked_hosts` / `runtime_allowed_hosts`.
- `URLAllowlist` is additive and restricts nothing on its own.

Intentional hardening, recorded rather than discovered later. `docs/reference/webapps.md` documents the two ways out
if it gets in the way.

Plan: `docs/drafts/chromium-webapps-plan-3-implement.md`. Operator docs: `docs/reference/webapps.md`.

## Test plan

- `nix flake check path:. --accept-flake-config --no-build --offline`
- `nix build path:.#nixosConfigurations.{tpnix,system76}.config.system.build.toplevel`
- `nix build path:.#nixosConfigurations.tpnix.config.home-manager.users.vx.home.packages`: builds every launcher, so
  `shellcheck` runs over each one. Eval alone does not reach the launcher body.
- `checks."browsers/webapps-policy"`: generated policy against a fixture, recomputed grants against the catalog, and
  the disjoint-key invariant against `_chromium-hardening.nix`. Drift proven detected by planting an extra origin in
  `VideoCaptureAllowedUrls`.
- `checks."browsers/webapps-keepalive-id"`: recomputes the keep-alive extension ID from its committed public key.
  Proven reachable by corrupting the transcribed ID.
- `checks."browsers/webapps-module-eval"`: forces the Home Manager module's `mkIf`-guarded output, which CI would
  otherwise never evaluate. Assertions proven reachable by inverting the tray expectation.
- Manual, on a real `brave-origin`: `--load-extension` against an
  `ExtensionSettings."*" = blocked` policy, to establish whether the keep-alive extension needs the allowlist entry
  (Task 10 Step 0).
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

Launch any web app, open a new tab to `brave://policy`, and confirm `AudioCaptureAllowed`, `VideoCaptureAllowedUrls`, `ScreenCaptureAllowedByOrigins`, `NotificationsAllowedForUrls`, `URLAllowlist` and `ExtensionSettings` are listed with status OK and no conflict warnings.

`ScreenCaptureAllowedByOrigins` gets particular attention: it is in the Chromium
registry, but Brave has removed and renamed capture policies before. A status of
"unknown policy" there means screen sharing is denied for Teams too, with the
allowlist inert.

- [ ] **Step 3: Confirm the keep-alive extension actually loaded**

Nothing before this proves it. The policy blocks every extension not named, the
generated one is loaded with `--load-extension`, and a blocked load is silent
outside `brave://extensions`.

In a keep-alive app (Teams or Outlook), open `brave://extensions`, enable
developer mode, and confirm:

- an entry named `<App> keep-alive` is present and enabled, not greyed out or
  labelled "Blocked by administrator";
- its ID matches `keepAliveExtensionId` in
  `modules/browsers/webapps/_keepalive-key.nix`;
- `brave://serviceworker-internals` lists a running service worker for it.

Compare the two IDs directly:

```bash
nix eval --raw --impure --expr \
  '(import /home/vx/nixos/modules/browsers/webapps/_keepalive-key.nix).keepAliveExtensionId'
jq -r '.ExtensionSettings | keys[]' /etc/brave/policies/managed/webapps.json
```

Expected: the first value appears in the second list.

If the extension is missing, re-read Task 10 Step 0: either the allowlist entry
is absent from `webapps.json`, or the ID in the policy does not match the ID
Chromium derived. Both are visible by diffing `brave://extensions` against
`jq '.ExtensionSettings | keys' /etc/brave/policies/managed/webapps.json`.

- [ ] **Step 4: Confirm the ID is stable across a rebuild**

The pinned manifest key exists so a rebuild does not orphan the extension in
every profile. Verify it once:

```bash
before="$(ls -1 "${XDG_DATA_HOME:-$HOME/.local/share}/webapps/teams/Extensions" 2>/dev/null)"
# rebuild and switch, then:
after="$(ls -1 "${XDG_DATA_HOME:-$HOME/.local/share}/webapps/teams/Extensions" 2>/dev/null)"
diff <(printf '%s\n' "$before") <(printf '%s\n' "$after")
```

Expected: no new directory. A second extension ID appearing after a rebuild
means the manifest `key` did not take effect and the profile will accumulate one
orphan per rebuild.

- [ ] **Step 5: Confirm isolation**

```bash
ls -la "${XDG_DATA_HOME:-$HOME/.local/share}/webapps"
```

Expected: one 0700 directory per app. Sign in to two different apps and confirm neither sees the other's session.

- [ ] **Step 6: Confirm the tray and keep-alive**

Launch Teams, confirm a tray icon appears in i3bar, close the window and confirm it iconifies rather than exiting, then confirm the process survives:

```bash
pgrep -af 'user-data-dir.*webapps/teams'
```

Leave it iconified for longer than `reload.intervalMinutes` and confirm the session is still authenticated on restore.

- [ ] **Step 7: Confirm notifications**

Trigger a notification from Outlook or Teams and confirm dunst renders it. Check attribution:

```bash
dunstctl history | jq -r '.data[0][] | {appname, summary}' 2>/dev/null | head
```

- [ ] **Step 8: Confirm what the browser-wide policy cost**

The denials in `webapps.json` apply to general browsing, so check the daily
driver rather than assuming. In a plain `brave-origin` window (no
`--user-data-dir`), open any site that asks for the camera or the microphone.

Expected: denied with no prompt. That is the documented behavior, not a bug. If
it is not acceptable in practice, the follow-up is one of the two options in
`docs/reference/webapps.md`; record which one was chosen and open an issue.

- [ ] **Step 9: Record any deviation**

If a Microsoft origin redirects out of its own host, or Visio and Clipchamp now resolve on Chromium, update
`modules/browsers/webapps/_catalog.nix` and refresh the policy fixture in a follow-up.

Update the two open questions in "Facts still to verify before implementing"
with what Steps 2 and 3 found, so the next reader is not re-testing them.

______________________________________________________________________

## Self-Review

**Spec coverage.** Every stated requirement maps to a task:

| Requirement                                                           | Where                                                         |
| --------------------------------------------------------------------- | ------------------------------------------------------------- |
| Complete firefoxpwa cleanup including extension and CLI               | Phase 2, Tasks 2-6                                            |
| Idiomatic, modular, reusable for many future apps                     | Tasks 9-12; keyed submodule plus a pure generator             |
| Working integrated notifications                                      | `permissions.notifications`, Task 10; verified Task 18 Step 5 |
| Opt-in backgrounding with a tray icon, default overridable per app    | `tray.{enable,icon}` plus `defaultTrayIcon`, Tasks 9 and 12   |
| Explicit per-app permissions, disabled by default                     | Task 10; deny-by-default plus per-origin allowlists           |
| Per-app profile, no shared cookies, sessions reused                   | Task 12; `--user-data-dir` per app                            |
| Configurable reload to prevent login timeout, works in the background | Task 11; `chrome.alarms` survives service-worker idling       |
| brave-origin as the base                                              | Tasks 7-8; verified it reads `/etc/brave/policies`            |
| Default extensions with per-app add and override                      | Task 10; `runtime_blocked_hosts` / `runtime_allowed_hosts`    |

**Known gaps, stated rather than hidden.**

- **The permission policy is browser-wide, not app-scoped.** Chromium applies a managed directory per browser, so `webapps.json` binds the daily-driver `brave-origin` too: mic, camera and screen share become promptless denials for all browsing outside `teams.cloud.microsoft`, extension installs are blocked in the main profile, and 1Password is force-installed there. Recorded in the Decisions table, in `docs/reference/webapps.md`, and in the PR body; verified in Task 18 Step 8. The escape hatches are a `brave` / `brave-origin` split or dropping the capture denies, both follow-ups.
- **Extensions are not isolated per app.** `--user-data-dir` separates cookies and storage; `ExtensionSettings` is managed policy and therefore browser-wide. `extensions.enable` installs an extension everywhere and scopes only interaction. The phrase "no two apps share cookies, storage or extensions" was wrong and is corrected everywhere it appeared.
- Geolocation cannot be granted per app. Chromium has no allowlist counterpart to `GeolocationBlockedForUrls`. Documented in `docs/reference/webapps.md` and omitted from the submodule rather than silently accepted and ignored.
- kdocker is X11 only. This matches the current i3 and lightdm setup (`modules/apps/i3wm/nixos.nix:75`) but would need replacing under Wayland.
- Each running app is a separate browser instance, roughly 250-400 MB baseline. Same cost firefoxpwa would have had with per-site profiles, but it bounds how many apps are worth leaving resident.
- `--load-extension` availability depends on the build not being Google-branded and on Enhanced Safe Browsing being off. Both hold for brave-origin under the hardened set (`SafeBrowsingProtectionLevel = 1`), but switching `programs.webapps.package` to Chrome would silently disable the keep-alive extension. Task 9's `package` option documents the constraint; consider an assertion if a second browser is ever supported.
- Visio and Clipchamp are excluded pending a Chromium re-test (Task 18 Step 9).
- Two facts are assumed rather than proven: that `ExtensionSettings` gates `--load-extension` (Task 10 Step 0) and that Brave honors `ScreenCaptureAllowedByOrigins` (Task 18 Step 2). Both have a named step and neither changes the plan's shape.
- `_check-apps.nix` restates the submodule defaults from `nixos.nix` and the default of `defaultExtensions`. Nothing enforces that they agree, so a new option default added to `nixos.nix` alone makes the fixture describe a policy the hosts do not get. The file header says so; a check that compares the two is a reasonable follow-up.

**Where validation would have missed a real failure.** Three cases the first draft of this plan would have passed:

- Task 12's launcher validated by `nix eval` on package names. `writeShellApplication` runs `shellcheck` at build time, so a malformed command body is a build failure that eval never reaches. An `lib.optionalString` inside a backslash-continued argument list rendered a whitespace-only line for every app without `reload.enable` and both tray wrappers, terminating the command early. Now validated with `nix build` plus reading back the two shapes that differ (Task 12 Step 4).
- `lib.getExe pkgs.diffutils` in Task 14 pointed at a `bin/diffutils` that does not exist, so the policy check would have failed on its own tooling. Now `lib.getExe' pkgs.diffutils "diff"`.
- `modules/browsers/webapps/apps.nix` would have been read as a catalog entry by `modules/meta/hooks/apps-catalog-sync.nix`, failing `pre-commit run --all-files --hook-stage manual` in Task 17 with `webapps` reported missing from `apps-enable.nix`, which Task 13 deliberately keeps it out of. The file is `nixos.nix`, and Task 13 Step 3 runs the hook rather than deferring it to Task 17.

**Type consistency.** `key`, `name`, `url`, `urlSecret`, `originSecret`, `permissions.*`, `extensions.{enable,disable}`, `tray.{enable,icon}` and `reload.{enable,intervalMinutes}` are used identically in `_catalog.nix`, `nixos.nix`, `_check-apps.nix`, `_policy.nix`, `home.nix`, `policy-check.nix` and `module-check.nix`. The `originPlaceholder` argument has the same `key -> string` signature at both call sites (`nixos.nix` and `_check-apps.nix`). `keepAliveExtensionId` is a plain `str` at its three call sites (`nixos.nix`, `_check-apps.nix`, `keepalive-id-check.nix`) and is the value `_reload-extension.nix` bakes into the manifest through `publicKey`.
