# Apps module header block

Every file under `modules/apps/` opens with a C-style block comment, `/* ... */`, as `modules/apps/ent.nix` does.

## Fields

The fields come first, in this order:

- `Package:` the app name matching the filename.
- `Description:` a one-sentence summary.
- `Homepage:` the primary product landing page.
- `Documentation:` the canonical manual, user guide, or reference docs.
  Prefer first-party sources; without one, use the homepage section that acts as the official documentation.
- `Repository:` the project repository URL, or `nil` when no public repository exists.

When `Homepage:`, `Documentation:`, and `Repository:` would all resolve to the same URL, set the first two to `nil` and keep only `Repository:`.

## Sections

The sections follow the fields, each separated by a blank line:

- `Summary:` bullets describing the primary functionality, usually two.
- `Tests:` only when upstream documents deterministic CLI output, as for `ent`.
  Without canonical tests, omit the section rather than inventing commands.
- `Options:` notable flags, switches, or usage notes, one line each, paraphrasing the official command documentation.
- `Notes:` optional implementation details, such as delegated responsibilities, namespace considerations, related packages, or the source flake of an external input.
  Omit it for a straightforward module.

`Summary`, `Tests`, and `Notes` use `*` bullets.
`Options` uses the literal option token as its bullet, such as `-b` in `modules/apps/ent.nix`.

## Documenting options

- Flag-based tools: the literal flags, such as `-f` or `--verbose`.
- Subcommand-based tools: the subcommand names, such as `init`, `generate`, or `onboard`.
- Tools with a minimal CLI: whatever exists, even one or two items.
- GUI or daemon tools: configuration patterns or notable behaviours.
- Library packages, such as Python or C libraries: the key API functions or classes.

When a project offers several front-ends, such as a CLI and a GUI, the comment covers the component the package delivers.
Unicode keeps the form upstream documentation uses, such as `π` in statistical descriptions.

## Sources

- Confirm every field against an authoritative source before editing a header.
- Start from the pinned nixpkgs expression for `description`, `homepage`, the version, and the upstream repository.
- Cross-check against primary sources, such as project docs, release notes, and the upstream README, through Context7, DeepWiki, or a web search.
- Confirm the manual or API reference URL resolves, following redirects, and prefer HTTPS endpoints the project owner maintains.
- Record which source satisfied each field in working notes, so a reviewer can replay the lookup.
- Revisit the header whenever options change or new capabilities ship.
