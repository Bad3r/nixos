# Documentation Instructions

Pages follow `technical-writing/style-guide.md`, which wins over the older pages
in that folder.

## Rules

- `index.md` shows what each folder holds. Placement it does not spell out:
  one folder per app, tool, or product under `apps/<name>/`; peripherals with
  their own module under `hardware/<class>/<device>/` and agent tooling under
  `agents/<name>/`, mirroring `modules/`; material spanning apps and hosts,
  including fleet-wide policy for one tool, under a topic folder such as
  `security/usbguard/`; unsettled plans under `drafts/`, which `docs-style`
  skips.
- Update an existing page before adding one, and search `docs/` for related
  content first.
- Update `index.md` when adding, removing, or moving a page.
- Folder and file names are lowercase and hyphenated, provider folders
  included: Cloudflare material lives under `apps/cloudflare/`.
- Link repo-relative, and keep host and user assumptions aligned with
  `modules/hosts/<host>/` and the `vx` user.
- When a page describes modules, options, or scripts, confirm them against the
  code in the same change.
