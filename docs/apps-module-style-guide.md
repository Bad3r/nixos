# Apps Module Style Guide

This guide defines the expectations for `modules/apps/<tool>.nix` files. Use it alongside `modules/apps/ent.nix`, which serves as the canonical template, and refer to `docs/configuration-architecture.md` for the bigger-picture aggregator and helper context.

## Source Gathering

- Before editing a module header, confirm every fact from an authoritative source.
- Start by inspecting the pinned nixpkgs expression for the package to capture `description`, `homepage`, current version, and upstream repository metadata.
- Use Context7 documentation fetches, DeepWiki repository insights, or an online search to cross-check details with official project documentation. Prioritize primary sources (project docs, release notes, upstream repository README).
- Identify the canonical user manual or API reference and verify that the URL resolves (follow redirects when necessary). Prefer HTTPS endpoints maintained by the project owner.
- Document which source satisfied each field in your working notes so reviewers can replay the lookup if needed.

## Scope

- Applies to every NixOS app module exported under `flake.nixosModules.apps`.
- Complements the repository-wide conventions noted in `docs/module-structure-guide.md`.

## File Layout

- Store each app module at `modules/apps/<tool>.nix`.
- Export the module as `flake.nixosModules.apps.<tool>`. Provide additional bundles (for example `workstation`, `base`) only when they are meaningful.
- Keep per-app modules focused on package enablement and lightweight configuration. Compose higher-level behaviour in domain modules (for example `modules/networking/`).

## Top-of-File Documentation Block

- Start every file with a C-style block comment: `/* ... */`.
- Populate the header in this order:
  - `Package:` — the app name matching the filename.
  - `Description:` — one-sentence summary.
  - `Homepage:` — primary product landing page.
  - `Documentation:` — canonical manual, user guide, or reference docs. Prefer first-party sources; if none exist, use the section of the homepage that acts as official documentation.
  - `Repository:` — upstream GitHub project URL when available. Omit only if no public GitHub repository exists.
- Provide the following subsections, each separated by a blank line:
  - `Summary:` — two bullet points describing primary functionality.
  - `Tests:` — only include when upstream documents deterministic CLI outputs (for example `ent.nix`). If no canonical tests exist, omit the section completely rather than inventing ad-hoc commands.
  - `Options:` — bullet list covering notable flags, switches, or usage notes. Use `-flag` entries to mirror CLI flags and keep bullets to one line each. Reference official command documentation when paraphrasing behaviour.
- Bullet style inside the comment:
  - Use `*` for generic bullet points (`Summary`, `Tests`).
  - Use the literal option token (for example `-b`) as the bullet for `Options`, as shown in `ent.nix`.
- Unicode characters are acceptable; retain the form used by upstream documentation (for example `π` in statistical descriptions).
- When a project offers multiple front-ends (for example CLI and GUI), scope the comment to the component delivered by the package.

## Module Body

- Define the module with the standard lambda: `{ pkgs, lib, ... }:`. Include `lib` only when used.
- Prefer `environment.systemPackages = [ pkgs.<tool> ];` for simple package exposure. Use `lib.mkDefault` when the package should remain optional, matching `ent.nix` if defaults are desired.
- Limit additional configuration to essentials required for the app to function.
- Maintain two-space indentation for attribute sets.

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

{
  flake.nixosModules.apps.example =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.example ];
    };
}
```

## Maintenance Checklist

- When adding a new app module, copy the skeleton, update the comment sections, and adjust bundles as required.
- Note the primary source used for each header field (nixpkgs, upstream docs, release notes).
- Run `nix fmt` after edits to preserve formatting.
- Review the header comment whenever options change or new capabilities ship to keep the documentation truthful.
