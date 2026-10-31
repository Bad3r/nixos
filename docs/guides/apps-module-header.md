# Apps module header block

Every app module, such as `modules/apps/<tool>.nix` or `modules/apps/<tool>/nixos.nix`, opens with a C-style block comment, `/* ... */`.

## Fields

The fields come first, in this order:

- `Package:` the app name, matching the file or folder name.
- `Description:` a one-sentence summary.
- `Homepage:` the primary product landing page. (Optional, if one exists.)
- `Documentation:` the canonical manual, user guide, or reference docs. (Optional, if one exists.)
- `Repository:` the project repository URL.

## Sections

The sections follow the fields, each separated by a blank line (all are optional):

- `Summary:` a description of the primary functionality.
- `Tests:` only when upstream documents deterministic CLI output, as for `ent`.
- `Options:` notable flags, switches, or subcommands.
- `Notes:` anything notable or important to know.

`Summary`, `Tests`, and `Notes` use `*` bullets.
`Options` uses the literal option token as its bullet, such as `-h` or `--help`.

## Sources

- Confirm against an up-to-date and current authoritative source, e.g. official docs or source code.
- Start from the pinned nixpkgs expression for `description`, `homepage`, the version, and the upstream repository.
