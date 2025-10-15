# RFC-0001 Role Taxonomy Reference

This document is the authoritative reference for the Freedesktop-aligned role
taxonomy introduced in [RFC-0001](../RFC-0001/RFC-0001-role-taxonomy-overhaul.md).
It records the canonical category roots, naming rules, metadata requirements,
and maintenance workflow so contributors can extend the taxonomy without
digging through implementation details.

## Canonical Categories

Roles reuse the AppStream category registry. Each root below comes from the
Freedesktop spec and maps to a canonical namespace under `roles.<root-slug>`.
Subroles are intentionally shallow (maximum of three segments — see
`lib/taxonomy/matrix.nix:maxSegments`).

| AppStream Root | Namespace Prefix    | Default Subroles                                                  | Vendor? | Notes                                                           |
| -------------- | ------------------- | ----------------------------------------------------------------- | ------- | --------------------------------------------------------------- |
| AudioVideo     | `roles.audio-video` | `media`, `production`, `streaming`                                | ✗       | Multimedia playback & creation bundles.                         |
| Development    | `roles.development` | `core`, language stacks (`python`, `go`, `rust`, `clojure`), `ai` | ✗       | Workstation language tooling and IDE helpers.                   |
| Education      | `roles.education`   | `research`, `learning-tools`                                      | ✗       | Reserved for future study/learning suites.                      |
| Game           | `roles.game`        | `launchers`, `tools`, `emulation`                                 | ✗       | Gaming launchers aggregate under `roles.game`.                  |
| Graphics       | `roles.graphics`    | `illustration`, `cad`, `photography`                              | ✗       | Creative / design applications.                                 |
| Network        | `roles.network`     | `sharing`, `tools`, `remote-access`, `services`                   | ✓       | Vendor integrations live under `roles.network.vendor.<vendor>`. |
| Office         | `roles.office`      | `productivity`, `planning`                                        | ✗       | Productivity and planning suites.                               |
| Science        | `roles.science`     | `data`, `visualisation`                                           | ✗       | Scientific tooling and visualisation stacks.                    |
| System         | `roles.system`      | `base`, `display.x11`, `storage`, `security`, `prospect`\*        | ✓       | Core OS bundles; `roles.system.vendor.<vendor>` is allowed.     |
| Utility        | `roles.utility`     | `cli`, `archive`, `monitoring`                                    | ✗       | Small CLI helpers and general-purpose utilities.                |

`prospect` is a reserved aggregation used to snapshot workstation parity;
avoid reusing it for general roles.

The matrix (source of truth for the table) lives in `lib/taxonomy/matrix.nix`.
Modify that file when introducing new subroles or enabling vendor namespaces.

## Versioning & Profiles

- **Current `TAXONOMY_VERSION`:** `0.1` (defined in `lib/taxonomy/version.nix`). Bump the major component when canonical namespaces change; bump the minor component when aliases or vocabulary expand. Update the `aliasHash` in the same file using the failure output from `nix build .#checks.x86_64-linux.phase0-taxonomy-version --accept-flake-config`.
- **Profiles consuming the taxonomy:** `flake.nixosModules.profiles.workstation` imports the canonical roles exclusively. Downstream hosts should prefer importing this profile (plus vendor roles) rather than reconstructing the role list manually.
- **Parity guard:** After modifying roles or manifests, run `nix build .#checks.x86_64-linux.phase4-workstation-parity --accept-flake-config` to compare `nixosConfigurations.system76` against `docs/RFC-0001/workstation-packages.json`. Regeneration guidance lives in `docs/RFC-0001/implementation-notes.md#phase-4-parity-validation`.

## Naming Rules

- Canonical role identifiers follow `roles.<root-slug>[.<subrole>[.<variant>]]`.
  - Roots are lowercase, hyphenated versions of the AppStream category name
    (for example, `AudioVideo` → `roles.audio-video`).
  - Nested segments must stay within the configured `maxSegments` (currently 3).
- Vendor integrations must live under `roles.<root>.vendor.<vendor-name>` and
  are only allowed for roots where `allowVendor = true` in the matrix
  (`roles.system` and `roles.network` today).
- Experiments or staging areas should be prefixed with `_` so the import tree
  ignores them by default (`modules/roles/_scratch/...`).
- Convenience aliases are managed in `lib/taxonomy/alias-registry.json`. Keep
  aliases stable for end users (`roles.dev`, `roles.media`, `roles.net`, …) and
  update the registry rather than renaming canonical modules. Modules for
  legacy aliases have been removed; all consumers resolve the canonical
  taxonomy directly.

## Metadata Requirements

Every canonical role module **must** export a `metadata` attribute validated by
`checks/phase0/metadata-lint.nix`. The metadata rules are enforced by the Phase 0
check suite and include:

1. `metadata.canonicalAppStreamId` (`AudioVideo`, `Development`, …) must match
   the AppStream root.
2. `metadata.categories[0]` must equal `canonicalAppStreamId` and all entries
   must come from `lib/taxonomy/freedesktop-categories.json` (or be prefixed
   with `X-` for explicit extensions).
3. Optional `auxiliaryCategories` follow the same validation; use these for
   additional search tags rather than redefining canonical roots.
4. `metadata.secondaryTags` is a free-form list constrained by internal
   vocabulary (`cli`, `asset`, `hardware-integration`, …). Keep additions small
   and document them in this file.
5. If a role imports vendor modules, ensure the vendor module’s metadata also
   satisfies the guardrails.

Packages that lack upstream AppStream data are patched through
`lib/taxonomy/metadata-overrides.json`. Regenerate overrides with
`./scripts/taxonomy-sweep.py` (documented in the implementation notes) whenever
package manifests change.

## Taxonomy Versioning & Alias Hash

`lib/taxonomy/version.nix` exposes:

- `taxonomyVersion = "<major>.<minor>"`
- `aliasHash = "<sha256>"`

Phase 0 uses these values to guarantee consumers bump versions intentionally.

- Bump **major** when canonical role paths change (breaking change).
- Bump **minor** when aliases, metadata vocabulary, or vendor policy expands.
- Recompute `aliasHash` by hashing the sorted alias list whenever
  `alias-registry.json` changes (`checks/phase0/taxonomy-version.nix` will fail
  until this happens).

The expected workflow:

1. Update `lib/taxonomy/alias-registry.json` (or other taxonomy data).
2. Run `nix build .#checks.x86_64-linux.phase0-taxonomy-version --accept-flake-config`
   to obtain the new hash from the failure output.
3. Patch `lib/taxonomy/version.nix` with the new `aliasHash` and adjust
   `taxonomyVersion` as described above.
4. Commit both changes together with a note in release docs.

## Contributor Checklist

- Read the RFC implementation notes (`docs/RFC-0001/implementation-notes.md`)
  before adding new roles.
- Use the helper scripts:
  - `scripts/list-role-imports.py --format json` – audit role payloads.
  - `scripts/taxonomy-sweep.py` – refresh metadata overrides and review queues.
- Keep Phase 0 checks red until the full migration is complete, but ensure the
  failure modes remain the expected sentinel errors (missing metadata, alias
  hash placeholder, etc.).
- Update this document whenever the matrix, vocabulary, or naming rules change.

For questions or divergent proposals, coordinate with the maintainer (`vx`) so
downstream hosts retain parity during the Phase 2 migration.

## Secondary Tag Vocabulary

Secondary tags describe extra attributes that help tooling distinguish assets,
CLI utilities, or vendor integrations. Current approved values (enforced by
`checks/phase0/metadata-lint.nix`) are:

- `asset`
- `cli`
- `formatter`
- `hardware-integration`

Tags are curated in `lib/taxonomy/metadata-overrides.json`. Additions should
include a short rationale in the overrides file and be reflected here.
