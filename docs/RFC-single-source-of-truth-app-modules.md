# RFC: Single Source of Truth for App Modules

## Summary

- Establish a single, typed source of truth for per‑app NixOS modules at `flake.lib.nixos.appModules`.
- Populate `flake.nixosModules.apps` centrally from that source, avoiding reliance on aggregator internals.
- Refactor roles to compose from the source via small helpers (`getApp`, `getApps`).
- Provide stable role aliases (`role-dev`, `role-media`, `role-net`) for host imports.

## Motivation

Current roles import per‑app modules via `with config.flake.nixosModules.apps; [ … ]`. This is brittle because the flake‑parts `nixosModules` option wraps and flattens modules, turning nested keys (e.g., `apps`) into a single module with `imports`, not a stable attrset of names. It leads to errors like undefined variables (`neovim`) or missing attributes (`roles.dev`), and couples roles to aggregator implementation details.

Additionally, deriving a stable view by reading `inputs.self.nixosModules.apps` while computing outputs risks self recursion and violates Nix best practices.

We want:

- Composability from modular per‑app definitions.
- A stable, explicit data source for app registry.
- A pattern that doesn’t depend on aggregator internals or `self` output peeking.

## Goals

- Define `flake.lib.nixos.appModules :: attrsOf deferredModule` as the canonical app registry.
- Expose `flake.nixosModules.apps` by importing all entries from `appModules`.
- Refactor roles (dev, media, net) to use helpers over the canonical registry.
- Introduce consistent role aliases: `role-dev`, `role-media`, `role-net`.

## Non‑Goals

- Changing the content or behavior of individual app modules beyond their export path.
- Home Manager restructure (can mirror later; out of scope for first pass).

## Critical Analysis

### Why not use `config.flake.nixosModules.apps` directly?

The flake‑parts aggregator maps `nixosModules` keys to modules with `imports`. Nested keys become a single module with `imports`, not an `attrsOf` of app functions. Relying on its post‑application shape is brittle and may break under changes to how the aggregator flattens or orders modules.

### Why not build the index from `inputs.self.nixosModules.apps`?

Referencing `inputs.self` outputs during output construction is a self recursion risk and contrary to Nix best practice. It also ties evaluation order to flake output materialization.

### Single Source of Truth Inversion

Moving the registry to `flake.lib.nixos.appModules` (data-first) avoids self recursion and dependency on aggregator internals. The aggregator then derives `nixosModules.apps` from this source through a single, explicit meta module. Roles consume the same data, ensuring consistency and clarity.

Trade‑offs:

- Pros: Clear separation of data (registry) and presentation (aggregator). Stable composition points. Easier testing and tooling. Eliminates circular evaluation risks.
- Cons: Touches many files to switch exports. Requires a migration phase and possible temporary compatibility shims.

Given our capacity and desire for correctness, the benefits outweigh the costs.

## Design

### Types and Options

- `options.flake.lib.nixos.appModules`
  - type: `lib.types.attrsOf lib.types.deferredModule`
  - default: `{ }`
  - description: Canonical registry of per‑app NixOS modules.

- `options.flake.lib.nixos.getApp`
  - type: `lib.types.functionTo lib.types.deferredModule`
  - default: `name: throw "getApp not initialized"`
  - description: Helper that resolves an app by name or throws with a clear error.

- `options.flake.lib.nixos.getApps`
  - type: `lib.types.functionTo (lib.types.listOf lib.types.deferredModule)`
  - default: `_names: throw "getApps not initialized"`
  - description: Helper that resolves a list of app names.

### Meta Module (Aggregator)

File: `modules/meta/apps-source-of-truth.nix`

- Provide the options above.
- Implement helpers:
  - `config.flake.lib.nixos.getApp = name: let m = config.flake.lib.nixos.appModules.${name} or null; in if m != null then m else throw "Unknown app '${name}' referenced by roles";`
  - `config.flake.lib.nixos.getApps = names: map config.flake.lib.nixos.getApp names;`
- Populate `flake.nixosModules.apps` from the registry:
  - `config.flake.nixosModules.apps = { imports = lib.attrValues config.flake.lib.nixos.appModules; };`

Optional compatibility bridge (removable later):

- For consumers expecting `nixosModules.apps.<name>`, mirror entries:
  - `config = lib.mkMerge (map (n: { flake.nixosModules.apps.${n} = config.flake.lib.nixos.appModules.${n}; }) (lib.attrNames config.flake.lib.nixos.appModules));`

### App Module Authoring Pattern

Before:

```nix
{ }
:
{
  flake.nixosModules.apps.neovim = { pkgs, ... }: { environment.systemPackages = [ pkgs.neovim ]; };
}
```

After (single source of truth):

```nix
let
  app = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.neovim ];
  };
in
{
  flake.lib.nixos.appModules.neovim = app;
}
```

Notes:

- Keep module values as functions when `pkgs`/args are needed, per repo style.
- Names stay consistent (camelCase names from filenames or explicitly chosen).

### Roles Refactor

Use helpers to compose imports from the canonical registry.

Example: `modules/roles/dev.nix`

```nix
{ config, ... }:
let
  getApps = config.flake.lib.nixos.getApps;
in
{
  flake.nixosModules.roles.dev.imports =
    getApps [
      "neovim" "vim" "cmake" "gcc" "gnumake" "pkg-config"
      "jq" "yq" "jnv" "tokei" "hyperfine" "git-filter-repo"
      "exiftool" "niv" "tealdeer" "httpie" "mitmproxy"
      "gdb" "valgrind" "strace" "ltrace" "vscodeFhs" "kiroFhs"
    ]
    ++ [ config.flake.nixosModules.dev.node ];

  flake.nixosModules."role-dev".imports = config.flake.nixosModules.roles.dev.imports;
}
```

Apply the same pattern to `roles/media.nix` and `roles/net.nix`, preserving any existing extra imports (e.g., `media` bundle).

### Stable Role Aliases

- `flake.nixosModules."role-dev".imports = config.flake.nixosModules.roles.dev.imports`
- `flake.nixosModules."role-media".imports = config.flake.nixosModules.roles.media.imports`
- `flake.nixosModules."role-net".imports = config.flake.nixosModules.roles.net.imports`

Hosts import alias modules for consistency:

```nix
(with config.flake.nixosModules; [
  workstation
  nvidia-gpu
]) ++ [
  config.flake.nixosModules."role-dev"
]
```

## Alternatives Considered

1. Keep using `config.flake.nixosModules.apps` with `with`

- Fragile: depends on aggregator’s internal shape. Nested keys are turned into a single module with `imports`.
- Breaks when flattened/merged—symbols become undefined.

2. Build an index from `inputs.self.nixosModules.apps`

- Risks self recursion and evaluation order issues.
- Reads outputs during output construction—against best practice.

3. Dual Binding (apps + index) per file

- Works, but duplicates export paths and risks drift.
- The single‑source inversion is cleaner and simpler to reason about.

## Migration Plan

1. Introduce the meta module

- Add `modules/meta/apps-source-of-truth.nix` defining options and wiring `nixosModules.apps` from `appModules`.
- Provide `getApp`, `getApps` helpers.
- Optionally enable the compatibility bridge.

2. Refactor app modules

- For each `modules/apps/*.nix`, export to `flake.lib.nixos.appModules.<name> = app`.
- Remove old `flake.nixosModules.apps.<name>` exports.
- Start with apps referenced by `dev/media/net` roles to keep the first pass small.

3. Refactor roles and bundles

- Switch to `getApps`/`getApp` for composing imports.
- Keep additional non‑app imports intact.

4. Add role aliases and update hosts

- Define `role-dev`, `role-media`, `role-net` alias modules.
- Update hosts to import alias modules.

5. Validate

- `nix flake check --accept-flake-config`
- `nix develop -c pre-commit run --all-files`
- `nix fmt`
- `generation-manager score` (target 90/90)

6. Remove compatibility bridge (optional)

- After confirming no consumers rely on `nixosModules.apps.<name>`.

## Risks and Mitigations

- Breadth of changes: Many files are touched. Mitigate with a clean, repeatable codemod pattern and pre‑commit validation.
- Typos in app names: `getApp`/`getApps` throw with a clear message; the error is caught at evaluation time.
- Hidden external consumers: Keep the compatibility bridge during rollout.

## Validation & Testing

- Flake evaluation: `nix flake show --accept-flake-config` should list `apps`, `roles`, and `role-*` modules.
- Full checks: `nix flake check --accept-flake-config` should pass.
- Smoke tests: Evaluate a subset of role compositions by name; ensure imports resolve.
- CI: Pre‑commit hooks (format/lint) must pass; `generation-manager score` remains ≥ 90/90.

## Open Questions

- Do we also standardize a single source for dev bundles (e.g., `flake.lib.nixos.devModules`)? Not required for this RFC; can be a follow‑up if needed.
- Do we mirror the same inversion for Home Manager apps? Mirroring would improve symmetry but is out of scope for this pass.

## Conclusion

The single‑source inversion centralizes the app registry under `flake.lib.nixos.appModules`, removing reliance on aggregator internals and preventing self recursion. Roles become simple, explicit compositions over a stable data source, and hosts import consistent role aliases. While the migration touches many files, it yields a cleaner, more maintainable architecture aligned with Nix best practices.
