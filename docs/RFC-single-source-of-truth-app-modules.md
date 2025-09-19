# RFC: Single Source of Truth for App Modules

## Context (September 2025)

- Role modules currently look up apps with `lib.hasAttrByPath` / `lib.getAttrFromPath` against `config.flake.nixosModules.apps`. This avoids the brittle `with config.flake.nixosModules.apps;` pattern and is already in production (`modules/roles/{dev,media,net}.nix`).
- Home Manager follows the same idea at the glue layer: roles are data in `flake.lib.homeManager.roles` and app modules live under `flake.homeManagerModules.apps.<name>`.
- App definitions still register themselves directly under `flake.nixosModules.apps.<name>`.

## Proposal Snapshot

Create a canonical registry under `flake.lib.nixos.appModules :: attrsOf deferredModule`, then:

1. Populate `flake.nixosModules.apps` automatically from that registry.
2. Expose helpers (`getApp`, `getApps`) alongside the data to remove repeated lookup logic.
3. Provide bridge aliases during migration so existing imports (`flake.nixosModules.apps.neovim`) continue to work.

## Rationale

- A central registry gives tooling a single place to inspect app availability.
- Roles would read from shared helpers rather than each re-implementing guard logic.
- Future automation (documentation, testing) can enumerate apps without poking at flake outputs.

## Migration Strategy (Not Started)

- [ ] Introduce `modules/meta/app-registry.nix` to declare the option, helpers, and bridge exports.
- [ ] Update every module under `modules/apps/` to write to `flake.lib.nixos.appModules.<name>`.
- [ ] Adjust roles to use `config.flake.lib.nixos.getApps`.
- [ ] Remove the bridge once all modules adopt the registry.

## Open Questions

- Should Home Manager mirror the same registry (`flake.lib.homeManager.appModules`)?
- Do we enforce naming conventions (e.g. lowercase camel case) via an option type?
- How do we test parity between the registry and the bridge during migration (pre-commit hook vs. CI script)?

## Status

Draft only. No code implements this RFC yet; guarded lookups remain the production approach. Contributors interested in pushing this forward should coordinate in an issue before starting the migration.
